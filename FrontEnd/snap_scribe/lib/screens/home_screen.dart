import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../widgets/image_display_widget.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> imageFiles = [];
  Map<String, dynamic> metadata = {};
  Map<String, bool> needsReuploadMap = {};
  String currentRecorderHash = "";
  String currentPlayerHash = "";
  String currentUploaderHash = "";
  String apiRoute = "http://35.228.135.177:5000/devices";
  late AudioRecorder _audioRecorder;
  late AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();

    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    // Listen to player state changes to detect when playback is finished
    _audioPlayer.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        if (_audioPlayer.playing) {  
          await _audioPlayer.stop();
        } 
        setState(() {
          currentPlayerHash = "";
        });
      }
    });
    _loadImages();
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
 
  Future<void> _loadImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final imageDir = Directory(join(directory.path, 'images'));
    final jsonFile = File(join(directory.path, 'image_metadata.json'));

    if (jsonFile.existsSync()) {
      final metadataJson = jsonFile.readAsStringSync();
      metadata = jsonDecode(metadataJson);

      imageFiles = [];
      for (var hash in metadata.keys) {
        final imagePath = join(imageDir.path, '$hash.jpg');
        final imageFile = File(imagePath);
        if (imageFile.existsSync()) {
          imageFiles.add(imageFile);
        }
      }
      setState(() {});
    }
  }

  Future<void> _snapImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      final imageBytes = await pickedFile.readAsBytes();
      final hash = _generateImageHash(imageBytes);
      final currentDateTime = DateTime.now().toIso8601String();

      final directory = await getApplicationDocumentsDirectory();
      final imageDir = Directory(join(directory.path, 'images'));
      if (!imageDir.existsSync()) {
        imageDir.createSync();
      }

      final imageFile = File(join(imageDir.path, '$hash.jpg'));
      await imageFile.writeAsBytes(imageBytes);

      metadata[hash] = {
        "isUploaded": false,
        "needsReupload": false,
        "hasAudio": false,
        "dateTime": currentDateTime,
      };

      final jsonFile = File(join(directory.path, 'image_metadata.json'));
      await jsonFile.writeAsString(jsonEncode(metadata));

      setState(() {
        imageFiles.add(imageFile);
      });
    }
  }

  String _generateImageHash(List<int> imageBytes) {
    return sha256.convert(imageBytes).toString();
  }

  Future<void> _startStopRecording(BuildContext context, String hash) async {
    final directory = await getApplicationDocumentsDirectory();
    final audioDir = Directory(join(directory.path, 'audio'));

    if (!audioDir.existsSync()) {
      audioDir.createSync();
    }

    final sameRecorder = currentRecorderHash == hash;

    final audioFile = File(join(audioDir.path, '$hash.wav'));
    if (currentRecorderHash != "") {
      // Show the loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      // Stop recording
      await _audioRecorder.stop();
      setState(() {  
        currentRecorderHash = "";
        metadata[hash]["hasAudio"] = true;
      });
      final jsonFile = File(join(directory.path, 'image_metadata.json'));
      await jsonFile.writeAsString(jsonEncode(metadata));

      Navigator.of(context, rootNavigator: true).pop();
    } 
    
    if(!sameRecorder)
    {
      if (_audioPlayer.playing) {  
        await _audioPlayer.stop();
        setState(() {
          currentPlayerHash = "";
        });
      } 
      // Start recording
      RecordConfig config = RecordConfig(encoder: AudioEncoder.wav);
      await _audioRecorder.start(
        config,
        path: audioFile.path
      );
      setState(() {
        currentRecorderHash = hash;
        if (metadata[hash]["isUploaded"])
        {
          metadata[hash]["needsReupload"] = true;
        }
      });
    }
  }

  Future<void> _togglePlayStopAudio(BuildContext context, String hash) async {
    final directory = await getApplicationDocumentsDirectory();
    final audioPath = join(directory.path, 'audio', '$hash.mp3');
    final audioFile = File(audioPath);

    if (audioFile.existsSync()) {
      final samePlayer = currentPlayerHash == hash;

      if (_audioPlayer.playing) {  
        // Show the loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Center(
              child: CircularProgressIndicator(),
            );
          },
        );

        await _audioPlayer.stop();
        setState(() {
          currentPlayerHash = "";
        });

        Navigator.of(context, rootNavigator: true).pop();
      } 
      
      if(!samePlayer)
      {
        setState(() {
          currentPlayerHash = hash;
        });
        await _audioPlayer.setFilePath(audioFile.path);
        await _audioPlayer.play();
      }
    }
  }

  Future<void> _showInfo(BuildContext context, String hash) async {
    try {
      // Show the loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      final url = Uri.parse(apiRoute + "/" + hash);

      // Send the media data (image + audio) as JSON
      final response = await http.get(url);

      if ( response.statusCode >= 200 && response.statusCode < 300) {
        // Successfully sent data to the API
        print('Data successfully uploaded: ${response.statusCode}');
        print('Response body: ${response.body}');
      } else {
        // Handle failure (any status code outside the 2xx range)
        print('Failed to upload data: ${response.statusCode}');
        print('Response body: ${response.body}');

        Navigator.of(context, rootNavigator: true).pop();

        return;
      }

      Map<String, dynamic> jsonResponse = jsonDecode(response.body);
      Map<String, dynamic> specificData = jsonDecode(jsonResponse["json_file"]);

      // Build a formatted string without { }
      String formattedData = specificData.entries.map((e) => "${e.key}: ${e.value}").join("\n");

      Navigator.of(context, rootNavigator: true).pop();

      // Show the formatted JSON in a dialog
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Image Info'),
            content: SingleChildScrollView(
              child: Text(
                formattedData,
                style: TextStyle(fontFamily: 'Courier', fontSize: 18),
              ),
            ),
            actions: [
              TextButton(
                child: Text('Close'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();

      // Handle error if fetching the data failed
      showDialog(
        context: context as BuildContext,
        builder: (context) {
          return AlertDialog(
            title: Text('Error'),
            content: Text('Failed to load data: $e'),
            actions: [
              TextButton(
                child: Text('Close'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _uploadImage(BuildContext context, String hash) async {
    // Show the loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    final directory = await getApplicationDocumentsDirectory();

    final imagePath = join(directory.path, 'images', '$hash.jpg');
    final imageFile = File(imagePath);

    final audioPath = join(directory.path, 'audio', '$hash.wav');
    final audioFile = File(audioPath);

    if (imageFile.existsSync()) {
      currentUploaderHash = hash;

      final apiPayload = {
        "id" : hash,
        "picture": base64Encode(await imageFile.readAsBytes()),
        "dateTime" : metadata[hash]["dateTime"],
      };

       // Add audio file if it exists
      if (audioFile.existsSync()) {
        apiPayload["voice"] = base64Encode(await audioFile.readAsBytes());
      }

      var response = null;

      if (metadata[hash]["needsReupload"])
      {
        final url = Uri.parse(apiRoute + "/" + hash);

        // Send the media data (image + audio) as JSON
        response = await http.put(
          url,
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonEncode(apiPayload),
        );
      }
      else
      {
        final url = Uri.parse(apiRoute);

        // Send the media data (image + audio) as JSON
        response = await http.post(
          url,
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonEncode(apiPayload),
        );
      }

      if ( response.statusCode >= 200 && response.statusCode < 300) {
        // Successfully sent data to the API
        print('Data successfully uploaded: ${response.statusCode}');
        print('Response body: ${response.body}');
        if( metadata[hash]["isUploaded"] )
        {
          metadata[hash]["needsReupload"] = false;
        }
        else
        {
          metadata[hash]["isUploaded"] = true;
        }
      } else {
        // Handle failure (any status code outside the 2xx range)
        print('Failed to upload data: ${response.statusCode}');
        print('Response body: ${response.body}');
        if( metadata[hash]["isUploaded"] )
        {
          metadata[hash]["needsReupload"] = true;
        }
      }

      setState(() {
        currentUploaderHash = "";
      });

      final jsonFile = File(join(directory.path, 'image_metadata.json'));
      await jsonFile.writeAsString(jsonEncode(metadata));
    }

    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF2E2E3A),
      appBar: AppBar(
        title: Text('Welcome to Snap Scribe!'),
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 50.0),
        child: Column(
          children: [
            Expanded(
              flex: 9,
              child: imageFiles.isEmpty
                  ? Center(
                      child: Text(
                        "Snap your first picture to begin!",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: imageFiles.length,
                      itemBuilder: (context, index) {
                        final hash = metadata.keys.elementAt(index);
                        final isUploaded = metadata[hash]["isUploaded"];
                        final needsReupload = metadata[hash]["needsReupload"];
                        final dateTimeISO = metadata[hash]["dateTime"];
                        final hasAudio = metadata[hash]["hasAudio"];
                        final formattedDateTime = _formatDateTime(dateTimeISO);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: ImageDisplayWidget(
                            imageFile: imageFiles[index],
                            title: formattedDateTime,
                            isUploaded: isUploaded,
                            needsReupload: needsReupload,
                            hasAudio: hasAudio,
                            isUploading: currentUploaderHash == hash,
                            isRecordingAudio: currentRecorderHash == hash,
                            isPlayingAudio: currentPlayerHash == hash,
                            onDelete: () => _deleteImage(context, hash),
                            onUpload: () => _uploadImage(context, hash),
                            onRecord: () => _startStopRecording(context, hash),
                            onPlayStopAudio: () => _togglePlayStopAudio(context, hash),
                            onShowInfo: () => _showInfo(context, hash),
                          ),
                        );
                      },
                    ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox.expand(
                  child: FloatingActionButton.extended(
                    onPressed: _snapImage,
                    icon: Icon(Icons.camera_alt, size: 30),
                    label: Text("Snap"),
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String isoDate) {
    final dateTime = DateTime.parse(isoDate);
    return "${dateTime.year}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.day.toString().padLeft(2, '0')} "
           "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}";
  }

  void _deleteImage(BuildContext context, String hash) async {
    // Show the loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    final directory = await getApplicationDocumentsDirectory();
    final imagePath = join(directory.path, 'images', '$hash.jpg');
    final imageFile = File(imagePath);

    if (imageFile.existsSync()) {
      await imageFile.delete();
      metadata.remove(hash);
      if (hash == currentUploaderHash) {
        currentUploaderHash = "";
      }
      if (hash == currentRecorderHash) {
        await _audioRecorder.stop();
        currentRecorderHash = "";
      }
      if (_audioPlayer.playing && hash == currentPlayerHash) { 
        await _audioPlayer.stop();
        currentPlayerHash = "";
      }
      final jsonFile = File(join(directory.path, 'image_metadata.json'));
      await jsonFile.writeAsString(jsonEncode(metadata));
      setState(() {
        imageFiles.removeWhere((file) => file.path == imageFile.path);
      });
    }

    final url = Uri.parse(apiRoute + "/" + hash);

    // Send the media data (image + audio) as JSON
    final response = await http.delete(url);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Successfully sent data to the API
      print('Data successfully deleted: ${response.statusCode}');
      print('Response body: ${response.body}');
    } else {
      // Handle failure (any status code outside the 2xx range)
      print('Failed to upload data: ${response.statusCode}');
      print('Response body: ${response.body}');
    }

    Navigator.of(context, rootNavigator: true).pop();
  }
}

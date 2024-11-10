import 'dart:io';
import 'package:flutter/material.dart';

class ImageDisplayWidget extends StatelessWidget {
  final File imageFile;
  final String title;
  final bool isUploaded;
  final bool needsReupload;
  final bool hasAudio;
  final bool isUploading;
  final bool isRecordingAudio;
  final bool isPlayingAudio;
  final VoidCallback onDelete;
  final VoidCallback onUpload;
  final VoidCallback onRecord;
  final VoidCallback onPlayStopAudio;
  final VoidCallback onShowInfo;

  ImageDisplayWidget({
    required this.imageFile,
    required this.title,
    required this.isUploaded,
    required this.needsReupload,
    required this.hasAudio,
    required this.isUploading,
    required this.isRecordingAudio,
    required this.isPlayingAudio,
    required this.onDelete,
    required this.onUpload,
    required this.onRecord,
    required this.onPlayStopAudio,
    required this.onShowInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: MediaQuery.of(context).size.width * 0.8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10)],
            ),
            child: Image.file(imageFile, fit: BoxFit.cover),
          ),
          SizedBox(height: 15),
          Text(
            title,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          SizedBox(height: 5),
          Text(
            'Uploaded: ${isUploaded && !needsReupload ? "Yes" : "No"}',
            style: TextStyle(
              fontSize: 22,
              color: isUploaded && !needsReupload ? Colors.green : Colors.red,
            ),
          ),
          SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  if (hasAudio && !isRecordingAudio) {
                    // Show confirmation only when trying to start recording and if audio exists
                    _showAudioOverrideConfirmation(context);
                  } else {
                    onRecord();
                  }
                }, // Record voice
                icon: Icon(
                  isRecordingAudio ? Icons.fiber_manual_record : Icons.mic, 
                  size: 40
                ),
                tooltip: 'Record Audio',
                color: isRecordingAudio ? Colors.red : Colors.blue,
                disabledColor: Colors.grey,
              ),
              SizedBox(width: 20),
              if (hasAudio) ...[
                IconButton(
                  onPressed: isRecordingAudio ? null : onPlayStopAudio,
                  icon: Icon(
                    isPlayingAudio ? Icons.stop : Icons.play_arrow,
                    size: 40
                  ),
                  tooltip: 'Play Audio',
                  color: isPlayingAudio ? Colors.red : Colors.green,
                  disabledColor: Colors.grey,
                ),
                SizedBox(width: 20),
              ],
              IconButton(
                onPressed: ((!isUploaded || needsReupload) && !isUploading && !isRecordingAudio) ? onUpload : null,
                icon: Icon(Icons.upload, size: 40),
                tooltip: 'Upload',
                color: Colors.orange,
                disabledColor: Colors.grey,
              ),
              SizedBox(width: 20),
              if (isUploaded) ...[
                IconButton(
                  onPressed: onShowInfo,
                  icon: Icon(Icons.info, size: 40),
                  tooltip: 'Info',
                  color: Colors.lightBlue,
                  disabledColor: Colors.grey,
                ),
                SizedBox(width: 20),
              ],
              IconButton(
                onPressed: () => _showDeleteConfirmation(context),
                icon: Icon(Icons.delete, size: 40),
                tooltip: 'Delete',
                color: Colors.red,
                disabledColor: Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAudioOverrideConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Override Audio'),
          content: Text('There is already an audio file associated with this image ($title). Do you want to override it?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Override'),
              onPressed: () {
                Navigator.of(context).pop();
                onRecord();
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Delete'),
          content: Text('Are you sure you want to delete the image taken at $title?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Delete'),
              onPressed: () {
                Navigator.of(context).pop();
                onDelete();
              },
            ),
          ],
        );
      },
    );
  }
}

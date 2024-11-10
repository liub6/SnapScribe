import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(SnapScribe());
}

class SnapScribe extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snap Scribe',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PermissionCheckScreen(),
    );
  }
}

class PermissionCheckScreen extends StatefulWidget {
  @override
  _PermissionCheckScreenState createState() => _PermissionCheckScreenState();
}

class _PermissionCheckScreenState extends State<PermissionCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  // Check permissions on start
  Future<void> _checkPermissions() async {
    // Request camera and microphone permissions
    PermissionStatus cameraStatus = await Permission.camera.request();
    PermissionStatus micStatus = await Permission.microphone.request();

    final hasPermissions = cameraStatus.isGranted && micStatus.isGranted;
    if (hasPermissions) {
      // Navigate to the home screen if permissions are granted
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      // Exit the app if permissions are denied
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

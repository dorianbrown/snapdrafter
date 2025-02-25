import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '/widgets/deck_scanner.dart';
import 'package:flutter/services.dart';

late CameraDescription _firstCamera;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  _firstCamera = cameras.first;

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: DeckScanner(camera: _firstCamera),
    ),
  );
}

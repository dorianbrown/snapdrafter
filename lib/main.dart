import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '/widgets/deck_scanner.dart';

late CameraDescription _firstCamera;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  _firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: DeckScanner(camera: _firstCamera),
    ),
  );
}

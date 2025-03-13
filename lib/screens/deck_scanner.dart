import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import 'image_processing_screen.dart';

class DeckScanner extends StatefulWidget {
  const DeckScanner({super.key});

  @override
  DeckScannerState createState() => DeckScannerState();
}

class DeckScannerState extends State<DeckScanner> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final double _pictureRotation = -90.0;

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = _createCameraController();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
  }

  Future<void> _createCameraController() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras.first,
        ResolutionPreset.max,
        enableAudio: false
    );
    _initializeControllerFuture = _controller.initialize();
    _initializeControllerFuture.then((_) {
      _controller.setFlashMode(FlashMode.off);
    });
    return _initializeControllerFuture;
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Scan Deck'), backgroundColor: Color.fromARGB(150, 0, 0, 0)),
        extendBodyBehindAppBar: true,
        body: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Center(child: RotatedBox(quarterTurns: -1, child: CameraPreview(_controller)));
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
        floatingActionButton: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 20,
            children: [
              FloatingActionButton.extended(
                heroTag: "Btn2",
                label: const Text("From File"),
                onPressed: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    img.Image inputImage = img.decodeImage(File(image.path).readAsBytesSync())!;
                    Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (context) => deckImageProcessing(inputImage: inputImage)
                        )
                    );
                  }
                },
                icon: const Icon(Icons.file_open),
              ),
              FloatingActionButton.extended(
                heroTag: "Btn3",
                label: const Text("Capture"),
                onPressed: () async {
                  img.Image inputImage = await _getInputImage();
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (context) => deckImageProcessing(inputImage: inputImage)
                      )
                  );
                },
                icon: const Icon(Icons.camera),
              )
            ]
        )
    );
  }

  Future<img.Image> _getInputImage() async {
    final picture = await _controller.takePicture();
    final bytes = await File(picture.path).readAsBytes();
    img.Image inputImage = img.decodeImage(bytes)!;
    inputImage = img.copyRotate(inputImage, angle: _pictureRotation);
    return inputImage;
  }

}
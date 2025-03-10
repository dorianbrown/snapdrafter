import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '/utils/data.dart';
import 'download_screen.dart';
import '/widgets/main_menu_drawer.dart';
import '/widgets/image_processing_screen.dart';

class DeckScanner extends StatefulWidget {
  const DeckScanner({super.key, required this.camera});

  final CameraDescription camera;

  @override
  DeckScannerState createState() => DeckScannerState();
}

class DeckScannerState extends State<DeckScanner> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late Future<void> _initializeDatabaseFuture;
  late DeckStorage _deckStorage;
  final double _pictureRotation = -90.0;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera,
        ResolutionPreset.max,
        enableAudio: false
    );

    _initializeControllerFuture = _controller.initialize();
    _initializeControllerFuture.then((_) {
      _controller.setFlashMode(FlashMode.off);
    });
    _initializeDatabaseFuture = _initializeDatabase();
    // Check if Scryfall data is downloaded, else launch screen
    _initializeDatabaseFuture.then((val) {
      _deckStorage.getScryfallMetadata().then((val) {
        if (val.isEmpty) {
          if (context.mounted) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const DownloadScreen()));
          }
        }
      });
    });
  }

  Future<void> _initializeDatabase() async {
    _deckStorage = DeckStorage();
    await _deckStorage.init().then((val) async {
      var decks = await _deckStorage.getAllDecks();
      debugPrint("Decks: $decks");
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Scan Deck')),
        drawer: MainMenuDrawer(),
        body: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Center(child: CameraPreview(_controller));
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
        floatingActionButton: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 20,
            children: [
              FloatingActionButton(
                heroTag: "Btn1",
                onPressed: () async {
                  final data = await rootBundle.load("assets/test_image.jpeg");
                  img.Image inputImage = img.decodeImage(data.buffer.asUint8List())!;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => deckImageProcessing(inputImage: inputImage)
                    )
                  );
                },
                child: const Icon(Icons.computer),
              ),
              FloatingActionButton.extended(
                heroTag: "Btn2",
                label: const Text("Upload"),
                onPressed: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    img.Image inputImage = img.decodeImage(File(image.path).readAsBytesSync())!;
                    Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (context) => deckImageProcessing(inputImage: inputImage)
                        )
                    );
                  }
                },
                icon: const Icon(Icons.upload),
              ),
              FloatingActionButton.extended(
                heroTag: "Btn3",
                label: const Text("Capture"),
                onPressed: () async {
                  img.Image inputImage = await _getInputImage();
                  Navigator.of(context).push(
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
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

import '/utils/data.dart';
import 'download_screen.dart';
import '/widgets/main_menu_drawer.dart';
import '/widgets/detection_preview.dart';

class DeckScanner extends StatefulWidget {
  const DeckScanner({super.key, required this.camera});

  final CameraDescription camera;

  @override
  DeckScannerState createState() => DeckScannerState();
}

class DeckScannerState extends State<DeckScanner> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late Future<void> _loadModelsFuture;
  late Future<void> _initializeDatabaseFuture;
  late Interpreter _detector;
  late TextRecognizer _textRecognizer;
  late DeckStorage _deckStorage;
  bool _modelsLoaded = false;
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
    _loadModelsFuture = _loadModels();
    _initializeDatabaseFuture = _initializeDatabase();
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

  Future<void> _loadModels() async {
    try {
      final options = InterpreterOptions();
      if (Platform.isAndroid) {
        // options.addDelegate(GpuDelegateV2());
      }

      final modelPath = 'assets/title_detection_yolov11_float16.tflite';
      _detector = await Interpreter.fromAsset(modelPath, options: options);
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      setState(() {
        _modelsLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading models: $e');
    }
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
    _detector.close();
    _textRecognizer.close();
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
                  if (_modelsLoaded) {
                    final data = await rootBundle.load("assets/test_image.jpeg");
                    img.Image inputImage = img.decodeImage(data.buffer.asUint8List())!;
                    _runCardDetection(inputImage);
                  }
                },
                child: const Icon(Icons.computer),
              ),
              FloatingActionButton.extended(
                heroTag: "Btn2",
                label: const Text("Upload"),
                onPressed: () async {
                  if (_modelsLoaded) {
                    final ImagePicker picker = ImagePicker();
                    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      img.Image inputImage = img.decodeImage(File(image.path).readAsBytesSync())!;
                      _runCardDetection(inputImage);
                    }
                  }
                },
                icon: const Icon(Icons.upload),
              ),
              FloatingActionButton.extended(
                heroTag: "Btn3",
                label: const Text("Capture"),
                onPressed: () async {
                  if (_modelsLoaded) {
                    img.Image inputImage = await _getInputImage();
                    _runCardDetection(inputImage);
                  };
                },
                icon: const Icon(Icons.camera),
              )
            ]
        )
    );
  }

  Future<void> _runCardDetection(img.Image inputImage) async {
    // 1. Take picture (or load from disk)
    // 2. Run titleDetection isolate
    // 3. for each detection: transcribeDetection isolate
    // 4. Combine these into output image.

    // TODO: Loading screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            Center(child: CircularProgressIndicator()),
      ),
    );

    // Yolo title detection
    List<List<int>> detections = _titleDetection(inputImage);

    List<Future<String>> detectionTextFutures = detections
        .map((detection) => _transcribeDetection(detection, inputImage))
        .toList();

    List<String> detectionText = await Future.wait(detectionTextFutures);

    // Add annotations to image
    img.Image outputImage = img.adjustColor(inputImage, brightness: 0.5);
    for (var i = 0; i<detections.length; i++) {
      var [x1, y1, x2, y2] = detections[i];
      // Draw bounding box around detected title
      img.drawRect(
        outputImage,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: img.ColorRgba8(255, 242, 0, 255),
        thickness: 5,
      );
      // Add text to image
      img.drawString(inputImage, detectionText[i],
          font: img.arial48,
          x: x1,
          y: y1 - 55,
          color: img.ColorRgba8(255, 242, 0, 255)
      );
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DetectionPreviewScreen(
            image: outputImage, detections: detectionText),
      ),
    );
  }

  Future<img.Image> _getInputImage() async {
    final picture = await _controller.takePicture();
    final bytes = await File(picture.path).readAsBytes();
    img.Image inputImage = img.decodeImage(bytes)!;
    inputImage = img.copyRotate(inputImage, angle: _pictureRotation);
    return inputImage;
  }

  List<List<int>> _titleDetection(img.Image inputImage) {
    final double detectionThreshold = 0.5;

    // Getting input/output shapes
    final input = _detector.getInputTensor(0); // BWHC
    final output = _detector.getOutputTensor(0); // BXYXYC
    int inputW = input.shape[1];
    int inputH = input.shape[2];

    // Resizing image for model
    final resizedImage = img.copyResize(
      inputImage,
      width: inputH,
      height: inputH,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(0, 0, 0, 255),
    );

    // Initializing input/output tensors
    final inputTensor = List<double>
        .filled(input.shape.reduce((a, b) => a * b), 0)
        .reshape(input.shape);
    final outputTensor = List<double>
        .filled(output.shape.reduce((a, b) => a * b), -1)
        .reshape(output.shape);

    // Filling input tensor with image data
    for (int y = 0; y < inputH; y++) {
      for (int x = 0; x < inputW; x++) {
        final pixel = resizedImage.getPixel(x, y);
        inputTensor[0][y][x][0] = pixel.r / 255.0;
        inputTensor[0][y][x][1] = pixel.g / 255.0;
        inputTensor[0][y][x][2] = pixel.b / 255.0;
      }
    }

    // Running of actual Yolo detection model
    _detector.run(inputTensor, outputTensor);

    // Converting output detection dimensions back to full
    // image dimensions
    bool isPortrait = inputImage.width < inputImage.height;
    int scalingFactor = isPortrait ? inputImage.height : inputImage.width;
    double widthPadding = isPortrait ? (inputImage.height - inputImage.width) / 2 : 0.0;
    double heightPadding = !isPortrait ? (inputImage.width - inputImage.height) / 2 : 0.0;

    List<List<int>> detections = (outputTensor[0] as List<List<double>>)
        .where((element) => (element[4] > detectionThreshold))
        .map((el) => [
          (el[0] * scalingFactor - widthPadding).toInt(),
          (el[1] * scalingFactor - heightPadding).toInt(),
          (el[2] * scalingFactor - widthPadding).toInt(),
          (el[3] * scalingFactor - heightPadding).toInt()
        ])
        .toList();

    return detections;
  }

  Future<String> _transcribeDetection(List<int> detection, img.Image inputImage) async {
    // Extract only relevant part from inputImage
    var [x1, y1, x2, y2] = detection;
    debugPrint("Detection: $detection");
    img.Image detectionImg = img.copyCrop(inputImage,
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1
    );
    // Convert img.Image to MLKit inputImage
    // TODO: Figure out how to do this in memory
    Directory tmpDir = await getTemporaryDirectory();
    File tmpFile = File('${tmpDir.path}/thumbnail_${x1}_${x2}_${y1}_${y2}.png');
    await img.encodeImageFile(tmpFile.path, detectionImg);
    final detectionImage = InputImage.fromFilePath(tmpFile.path);
    // Run MLKit text recognition
    final RecognizedText recognizedText = await _textRecognizer.processImage(detectionImage);
    debugPrint("Text: ${recognizedText.text}");
    return recognizedText.text;
  }
}
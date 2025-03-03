import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
  List<String> detections = [];
  bool _modelsLoaded = false;
  double _pictureRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera,
        ResolutionPreset.ultraHigh,
        enableAudio: false
    );
    _initializeControllerFuture = _controller.initialize();
    _loadModelsFuture = _loadModels();
    _initializeDatabaseFuture = _initializeDatabase();
    _initializeDatabaseFuture.then((val) {
      _deckStorage.populateSetsTable();
      _deckStorage.getScryfallMetadata().then((val) {
        if (val.isEmpty) {
          if (context.mounted) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const DownloadScreen()));
          }
        }
      });
    });

    // Used for ensuring Detection photo has correct orientation
    accelerometerEventStream(
        samplingPeriod: Duration(seconds: 1)
    ).listen((AccelerometerEvent event) {
      if (event.x < 0.7 && event.x > -0.7) {
        _pictureRotation = 0.0;
      } else if (event.x > 0.7) {
        _pictureRotation = -90.0;
      } else if (event.x < -0.7) {
        _pictureRotation = 90.0;
      }
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

  Future<List<List<double>>> _runInference(img.Image image) async {
    final input = _detector.getInputTensor(0); // BWHC
    final output = _detector.getOutputTensor(0); // BXYXYC

    int inputW = input.shape[1];
    int inputH = input.shape[2];

    final resizedImage = img.copyResize(
      image,
      width: inputH,
      height: inputH,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(0, 0, 0, 255),
    );

    final inputTensor =
    List<double>.filled(input.shape.reduce((a, b) => a * b), 0)
        .reshape(input.shape);
    final outputTensor =
    List<double>.filled(output.shape.reduce((a, b) => a * b), -1)
        .reshape(output.shape);

    for (int y = 0; y < inputH; y++) {
      for (int x = 0; x < inputW; x++) {
        final pixel = resizedImage.getPixel(x, y);
        inputTensor[0][y][x][0] = pixel.r / 255.0;
        inputTensor[0][y][x][1] = pixel.g / 255.0;
        inputTensor[0][y][x][2] = pixel.b / 255.0;
      }
    }

    Stopwatch stopWatch = Stopwatch()..start();
    _detector.run(inputTensor, outputTensor);
    stopWatch.stop();
    debugPrint("Time for inference ${stopWatch.elapsed.inMilliseconds}ms");
    return outputTensor[0];
  }

  Future<img.Image> _processImage(img.Image inputImage) async {
    double widthPadding;
    double heightPadding;
    int scalingFactor;
    if (inputImage.width < inputImage.height) {
      widthPadding = (inputImage.height - inputImage.width) / 2;
      heightPadding = 0.0;
      scalingFactor = inputImage.height;
    } else {
      widthPadding = 0.0;
      heightPadding = (inputImage.width - inputImage.height) / 2;
      scalingFactor = inputImage.width;
    }
    inputImage = img.adjustColor(inputImage, brightness: 0.5);

    // Make global list of detections empty before running detection
    detections = [];
    final boundingBoxes = await _runInference(inputImage);
    final threshold = 0.5;

    for (var i = 0; i < boundingBoxes.length; i++) {
      var detection = boundingBoxes[i];
      if (detection[4] > threshold) {
        int x1 = (detection[0] * scalingFactor - widthPadding).toInt();
        int y1 = (detection[1] * scalingFactor - heightPadding).toInt();
        int x2 = (detection[2] * scalingFactor - widthPadding).toInt();
        int y2 = (detection[3] * scalingFactor - heightPadding).toInt();

        img.Image detectionImg = img.copyCrop(inputImage,
            x: x1, y: y1, width: x2 - x1, height: y2 - y1);

        Directory tmpDir = await getTemporaryDirectory();
        File tmpFile = File('${tmpDir.path}/thumbnail.png');
        await img.encodeImageFile(tmpFile.path, detectionImg);

        final detectionImage = InputImage.fromFilePath(tmpFile.path);
        final RecognizedText recognizedText =
        await _textRecognizer.processImage(detectionImage);
        detections.add(recognizedText.text);
        debugPrint("recognizedText");

        img.drawRect(
          inputImage,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: img.ColorRgba8(255, 242, 0, 255),
          thickness: 5,
        );

        img.drawString(inputImage, recognizedText.text,
            font: img.arial48,
            x: x1,
            y: y1 - 55,
            color: img.ColorRgba8(255, 242, 0, 255));
      }
    }

    return inputImage;
  }

  Future<void> _takePictureAndProcess({bool debug = false}) async {
    try {
      await _initializeControllerFuture;
      await _loadModelsFuture;
      await _initializeDatabaseFuture;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Center(child: CircularProgressIndicator()),
        ),
      );


      img.Image inputImage;
      if (debug) {
        final data = await rootBundle.load("assets/test_image.jpeg");
        inputImage = img.decodeImage(data.buffer.asUint8List())!;
      } else {
        final picture = await _controller.takePicture();
        final bytes = await File(picture.path).readAsBytes();
        inputImage = img.decodeImage(bytes)!;
        inputImage = img.copyRotate(inputImage, angle: _pictureRotation);
      }

      final processedImage = await _processImage(inputImage);

      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DetectionPreviewScreen(
              image: processedImage, detections: detections),
        ),
      );
    } catch (e) {
      debugPrint('Error processing image: $e');
    }
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
                onPressed: () {
                  _modelsLoaded ? _takePictureAndProcess(debug: true) : null;
                },
                child: const Icon(Icons.computer),
              ),
              FloatingActionButton(
                heroTag: "Btn2",
                onPressed: () {
                  _modelsLoaded ? _takePictureAndProcess(debug: false) : null;
                },
                child: const Icon(Icons.camera_alt),
              )
            ]));
  }
}
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'utils/image.dart';

late CameraDescription _firstCamera;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  _firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(camera: _firstCamera),
    ),
  );
}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key, required this.camera});

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late Interpreter _detector;
  late TextRecognizer _textRecognizer;
  List detections = [];
  bool _modelsLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
        widget.camera,
        ResolutionPreset.high  // not ultra-high to possibly speed up app
    );
    _initializeControllerFuture = _controller.initialize();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final options = InterpreterOptions();
      if (Platform.isAndroid) {
        // options.addDelegate(GpuDelegateV2());
      }

      final modelPath = 'assets/title_detection_yolov11_float16.tflite';
      _detector = await Interpreter.fromAsset(modelPath, options: options);
      _textRecognizer = await TextRecognizer(script: TextRecognitionScript.latin);
      setState(() {
        _modelsLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading models: $e');
    }
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
    final output = _detector.getOutputTensor(0);  // BXYXYC

    int input_w = input.shape[1];
    int input_h = input.shape[2];

    final resizedImage = img.copyResize(
      image,
      width: input_h,
      height: input_h,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(0, 0, 0, 255),
    );

    final inputTensor = List<double>.filled(input.shape.reduce((a, b) => a * b), 0).reshape(input.shape);
    final outputTensor = List<double>.filled(output.shape.reduce((a, b) => a * b), -1).reshape(output.shape);

    for (int y = 0; y < input_h; y++) {
      for (int x = 0; x < input_w; x++) {
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

  Future<img.Image> _processImage(String imagePath) async {
    // final bytes = await File(imagePath).readAsBytes();
    // final original_image = img.decodeImage(bytes)!;
    // final image_copy = img.bakeOrientation(original_image);  // Not sure if this does what I want
    final data = await rootBundle.load("assets/test_image.jpeg");
    final img.Image original_image = img.decodeImage(data.buffer.asUint8List())!;
    final image_copy = img.bakeOrientation(original_image);

    debugPrint("Captured image: ${original_image.width}x${original_image.height}");

    double widthPadding;
    double heightPadding;
    int scalingFactor;
    if (image_copy.width < image_copy.height) {
      widthPadding = (image_copy.height - image_copy.width) / 2;
      heightPadding = 0.0;
      scalingFactor = image_copy.height;
    } else {
      widthPadding = 0.0;
      heightPadding = (image_copy.width - image_copy.height) / 2;
      scalingFactor = image_copy.width;
    }

    final detections = await _runInference(image_copy);
    final threshold = 0.5;

    for (var i=0; i < detections.length; i++) {
      var detection = detections[i];
      if (detection[4] > threshold) {
        int x1 = (detection[0] * scalingFactor - widthPadding).toInt();
        int y1 = (detection[1] * scalingFactor - heightPadding).toInt();
        int x2 = (detection[2] * scalingFactor - widthPadding).toInt();
        int y2 = (detection[3] * scalingFactor - heightPadding).toInt();
        double conf = detection[4];
        double angle = detection[5];
        debugPrint("x1: $x1, y1: $y2, x2: $x2, y2: $y2, conf: $conf, angle: $angle");

        img.Image detectionImg = img.copyCrop(
            original_image,
            x: x1,
            y: y1,
            width: x2-x1,
            height: y2-y1
        );

        final detectionJpg = img.encodeJpg(detectionImg);
        final newFilePath = imagePath.replaceAll(".jpg", "_detection_$i.jpg");
        await File(newFilePath).writeAsBytes(detectionJpg);

        final detectionImage = InputImage.fromFilePath(newFilePath);
        final RecognizedText recognizedText = await _textRecognizer.processImage(detectionImage);
        debugPrint("Recognized text: ${recognizedText.text}");

        img.drawRect(
          image_copy,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: img.ColorRgba8(255, 242, 0, 255),
          thickness: 5,
        );

        img.drawString(
            image_copy,
            recognizedText.text,
            font: img.arial48,
            x: x1,
            y: y1 - 55,
            color: img.ColorRgba8(255, 242, 0, 255)
        );
      }
    }

    return image_copy;
  }

  Future<void> _takePictureAndProcess() async {
    try {
      await _initializeControllerFuture;

      final picture = await _controller.takePicture();
      final processedImage = await _processImage(picture.path);
      final jpg = img.encodeJpg(processedImage);
      final newFilePath = picture.path.replaceAll(".jpg", "_detections.jpg");
      await File(newFilePath).writeAsBytes(jpg);

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(imagePath: newFilePath),
        ),
      );
    } catch (e) {
      debugPrint('Error processing image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
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
      floatingActionButton: FloatingActionButton(
        onPressed: _modelsLoaded ? _takePictureAndProcess : null,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

class MainMenuDrawer extends StatelessWidget {
  const MainMenuDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 120,
              child: DrawerHeader(
                decoration: BoxDecoration(color: Colors.blue),
                child: Text('Decklist Scanner'),
                padding: EdgeInsets.fromLTRB(15, 40, 0, 0),
              ),
            ),
            ListTile(
              title: const Text('Scan Deck'),
              onTap: () {
                Navigator.of(context).popUntil(ModalRoute.withName('/'));
              },
            ),
            ListTile(
              title: const Text('View My Decks'),
              onTap: () {
                Navigator.of(context).popUntil(ModalRoute.withName('/'));
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const MyDecksView())
                );
              },
            ),
          ],
        )
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;

  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      // TODO: Make this zoom to whole viewcreen.
      body: Center(
          child: InteractiveViewer(child: Image.file(File(imagePath)))
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: null,
          label: Text("Save Deck"),
          icon: Icon(Icons.add)
      ),
    );
  }
}

class MyDecksView extends StatelessWidget {
  const MyDecksView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("My Decks")),
      drawer: MainMenuDrawer(),
      body: Center(
          child: Text("All the Decks!")
      )
    );
  }
}
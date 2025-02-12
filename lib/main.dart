import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(camera: firstCamera),
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
  late Interpreter _interpreter;
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
        widget.camera,
        ResolutionPreset.ultraHigh
    );
    _initializeControllerFuture = _controller.initialize();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final modelPath = 'assets/title_detection_yolov11_float32.tflite';
      _interpreter = await Interpreter.fromAsset(modelPath);
      setState(() {
        _modelLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading model: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _interpreter.close();
    super.dispose();
  }

  Future<List<List<double>>> _runInference(img.Image image) async {
    final resizedImage = img.copyResize(
      image,
      width: 2016,
      height: 2016,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(0, 0, 0, 255),
    );

    final inputTensor = List<double>.filled(2016 * 2016 * 3, 0).reshape([1, 2016, 2016, 3]);
    final outputTensor = List<double>.filled(6 * 300, -1).reshape([1, 300, 6]);

    for (int y = 0; y < 2016; y++) {
      for (int x = 0; x < 2016; x++) {
        final pixel = resizedImage.getPixel(x, y);
        inputTensor[0][y][x][0] = pixel.r / 255.0;
        inputTensor[0][y][x][1] = pixel.g / 255.0;
        inputTensor[0][y][x][2] = pixel.b / 255.0;
      }
    }

    debugPrint("Starting TFLite inference...");
    _interpreter.run(inputTensor, outputTensor);
    debugPrint("Finished TFLite inference");
    return outputTensor[0];
  }

  Future<img.Image> _processImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final tmp_image = img.decodeImage(bytes)!;
    final image = img.bakeOrientation(tmp_image);
    // final data = await rootBundle.load("assets/test_image.jpeg");
    // final img.Image image = img.decodeImage(data.buffer.asUint8List())!;

    double widthPadding;
    double heightPadding;
    int scalingFactor;
    if (image.width < image.height) {
      widthPadding = (image.height - image.width) / 2;
      heightPadding = 0.0;
      scalingFactor = image.height;
    } else {
      widthPadding = 0.0;
      heightPadding = (image.width - image.height) / 2;
      scalingFactor = image.width;
    }

    final detections = await _runInference(image);
    final threshold = 0.5;
    for (var detection in detections) {
      if (detection[4] > threshold) {
        int x1 = (detection[0] * scalingFactor - widthPadding).toInt();
        int y1 = (detection[1] * scalingFactor - heightPadding).toInt();
        int x2 = (detection[2] * scalingFactor - widthPadding).toInt();
        int y2 = (detection[3] * scalingFactor - heightPadding).toInt();
        double conf = detection[4];
        double angle = detection[5];
        debugPrint("x1: $x1, y1: $y2, x2: $x2, y2: $y2, conf: $conf, angle: $angle");

        img.drawRect(
          image,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: img.ColorRgba8(255, 242, 0, 255),
          thickness: 5,
        );
      }
    }
    return image;
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
      // appBar: AppBar(title: const Text('Take a picture')),
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
        onPressed: _modelLoaded ? _takePictureAndProcess : null,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;

  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: const Text('Display the Picture')),
      body: Center(child: Image.file(File(imagePath))),
    );
  }
}
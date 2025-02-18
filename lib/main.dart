import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'utils/image.dart';
import 'utils/data.dart';
import 'utils/models.dart' as models;

late CameraDescription _firstCamera;
late DeckStorage _deckStorage;

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
  List<String> detections = [];
  bool _modelsLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
        widget.camera,
        ResolutionPreset.high  // not ultra-high to possibly speed up app
    );
    _initializeControllerFuture = _controller.initialize();
    _loadModelsFuture = _loadModels();
    _initializeDatabaseFuture = _initializeDatabase();
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

    // Make global list of detections empty before running detection
    detections = [];
    final boundingBoxes = await _runInference(image_copy);
    final threshold = 0.5;

    for (var i=0; i < boundingBoxes.length; i++) {
      var detection = boundingBoxes[i];
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
        detections.add(recognizedText.text);

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
      await _loadModelsFuture;
      await _initializeDatabaseFuture;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Center(child: CircularProgressIndicator()),
        ),
      );

      final picture = await _controller.takePicture();
      final processedImage = await _processImage(picture.path);
      final jpg = img.encodeJpg(processedImage);
      final newFilePath = picture.path.replaceAll(".jpg", "_detections.jpg");
      await File(newFilePath).writeAsBytes(jpg);

      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DetectionPreviewScreen(
            imagePath: newFilePath,
            detections: detections
          ),
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
                  MaterialPageRoute(builder: (context) => const MyDecksOverview())
                );
              },
            ),
          ],
        )
    );
  }
}

class DetectionPreviewScreen extends StatelessWidget {
  final String imagePath;
  final List<String> detections;

  const DetectionPreviewScreen({super.key, required this.imagePath, required this.detections});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      // TODO: Make this zoom to whole viewcreen.
      body: Center(
          child: InteractiveViewer(child: Image.file(File(imagePath)))
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Center(child: CircularProgressIndicator()),
              ),
            );
            final deckId = await createDeckAndSave(detections);
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => DecklistViewer(deckId: deckId),
                ),
                ModalRoute.withName('/')
            );
            // Go to Route ViewDeck(deck_id)
            // Make sure to adjust route to go back to 'My Decks'
          },
          label: Text("Save Deck"),
          icon: Icon(Icons.add)
      ),
    );
  }

  Future<int> createDeckAndSave(List<String> detections) async {
    final allCards = await _deckStorage.getAllCards();
    final choices = allCards.map((card) => card.title).toList();
    final List<models.Card> matchedCards = [];
    debugPrint("Matching detections with database");
    for (final detection in detections) {
      final match = extractOne(
          query: detection,
          choices: choices
      );
      debugPrint(match.toString());
      debugPrint(allCards[match.index].toString());
      matchedCards.add(allCards[match.index]);
    }
    final String deckName = "Draft Deck";
    final DateTime dateTime = DateTime.now();
    return await _deckStorage.saveDeck(deckName, dateTime, matchedCards);
  }

}

class MyDecksOverview extends StatelessWidget {
  const MyDecksOverview({super.key});

  @override
  Widget build(BuildContext context) {

    final TextStyle dataColumnStyle = TextStyle(fontWeight: FontWeight.bold);

    return Scaffold(
      appBar: AppBar(title: Text("My Decks")),
      drawer: MainMenuDrawer(),
      body: Container(
        alignment: Alignment.topCenter,
        child: DataTable(
          columns: [
            DataColumn(label: Text("Deck Name", style: dataColumnStyle)),
            DataColumn(label: Text("Date", style: dataColumnStyle)),
          ],
          rows: [
            DataRow(
              cells: [
                DataCell(GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => DecklistViewer(deckId: 1))
                    );
                  },
                  child: Text("Test Deck Name 1"),
                )),
                DataCell(Text("2024/03/01"))
            ]),
            DataRow(cells: [
              DataCell(GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => DecklistViewer(deckId: 2))
                  );
                },
                child: Text("Test Deck Name 2"),
              )),
              DataCell(Text("2024/03/01"))
            ])
          ]
        )
      )
    );
  }
}

class DecklistViewer extends StatelessWidget {
  final int deckId;

  const DecklistViewer({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    Future<List> decks = _deckStorage.getAllDecks();
    return FutureBuilder<void>(
        future: decks,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(),
            );
          } else {
            return Scaffold(
              appBar: AppBar(title: Text("$deckId")),
              body: Text("Work in Progess")
            );
          }
          // final models.Deck currentDeck = decks[snapshot.data];
        }
    );
  }
}
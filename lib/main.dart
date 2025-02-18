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
        ResolutionPreset.ultraHigh  // not ultra-high to possibly speed up app
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
    final bytes = await File(imagePath).readAsBytes();
    final originalImage = img.decodeImage(bytes)!;
    final imageCopy = img.bakeOrientation(originalImage);  // Not sure if this does what I want
    // final data = await rootBundle.load("assets/test_image.jpeg");
    // final img.Image originalImage = img.decodeImage(data.buffer.asUint8List())!;
    // final imageCopy = img.bakeOrientation(originalImage);

    debugPrint("Captured image: ${originalImage.width}x${originalImage.height}");

    double widthPadding;
    double heightPadding;
    int scalingFactor;
    if (imageCopy.width < imageCopy.height) {
      widthPadding = (imageCopy.height - imageCopy.width) / 2;
      heightPadding = 0.0;
      scalingFactor = imageCopy.height;
    } else {
      widthPadding = 0.0;
      heightPadding = (imageCopy.width - imageCopy.height) / 2;
      scalingFactor = imageCopy.width;
    }

    // Make global list of detections empty before running detection
    detections = [];
    final boundingBoxes = await _runInference(imageCopy);
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
            originalImage,
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
          imageCopy,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: img.ColorRgba8(255, 242, 0, 255),
          thickness: 5,
        );

        img.drawString(
            imageCopy,
            recognizedText.text,
            font: img.arial48,
            x: x1,
            y: y1 - 55,
            color: img.ColorRgba8(255, 242, 0, 255)
        );
      }
    }

    return imageCopy;
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
    Future<List<models.Deck>> decksFuture = _deckStorage.getAllDecks();
    final TextStyle dataColumnStyle = TextStyle(fontWeight: FontWeight.bold);
    return FutureBuilder<List<models.Deck>>(
        future: decksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(),
            );
          } else {
            final List<models.Deck>? decks = snapshot.data;
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
                    ...generateDataRows(decks, context)
                  ]
                )
              )
            );
          }
        }
    );
  }

  List<DataRow> generateDataRows(List<models.Deck>? decks, context) {
    var dataRowList = decks?.map((deck) {
      return DataRow(cells: [
        DataCell(GestureDetector(
          onTap: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => DecklistViewer(deckId: 1))
            );
          },
          child: Text("Test Deck Name 1"),
        )),
        DataCell(Text("2024/03/01"))
      ]);
    }).toList();
    if (dataRowList != null) {
      return dataRowList;
    } else {
      return [];
    }
  }
}

class DecklistViewer extends StatelessWidget {
  final int deckId;
  const DecklistViewer({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    Future<List<models.Deck>> decksFuture = _deckStorage.getAllDecks();
    return FutureBuilder<List<models.Deck>>(
        future: decksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(),
            );
          } else {
            final List<models.Deck>? decks = snapshot.data;
            final deck = decks?[deckId - 1];
            return Scaffold(
              appBar: AppBar(title: Text("${deck?.name}")),
              body: Container(
                margin: EdgeInsets.fromLTRB(50, 25, 50, 25),
                alignment: Alignment.topCenter,
                child: ListView(
                  children: [
                    Text("Date: ${deck?.dateTime.toIso8601String()}"),
                    Divider(),
                    Text("Cards:"),
                    for (final card in deck?.cards ?? [])
                      Text(card.title),
                  ],
                ),
              )
            );
          }
          // final models.Deck currentDeck = decks[snapshot.data];
        }
    );
  }
}
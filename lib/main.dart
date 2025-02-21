import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';


import 'utils/utils.dart';
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

    // Make global list of detections empty before running detection
    detections = [];
    final boundingBoxes = await _runInference(inputImage);
    final threshold = 0.5;

    for (var i=0; i < boundingBoxes.length; i++) {
      var detection = boundingBoxes[i];
      if (detection[4] > threshold) {
        int x1 = (detection[0] * scalingFactor - widthPadding).toInt();
        int y1 = (detection[1] * scalingFactor - heightPadding).toInt();
        int x2 = (detection[2] * scalingFactor - widthPadding).toInt();
        int y2 = (detection[3] * scalingFactor - heightPadding).toInt();

        img.Image detectionImg = img.copyCrop(
            inputImage,
            x: x1,
            y: y1,
            width: x2-x1,
            height: y2-y1
        );

        Directory tmp_dir = await getTemporaryDirectory();
        File tmp_file = File('${tmp_dir.path}/thumbnail.png');
        await img.encodeImageFile(tmp_file.path, detectionImg);

        final detectionImage = InputImage.fromFilePath(tmp_file.path);
        final RecognizedText recognizedText = await _textRecognizer.processImage(detectionImage);
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

        img.drawString(
            inputImage,
            recognizedText.text,
            font: img.arial48,
            x: x1,
            y: y1 - 55,
            color: img.ColorRgba8(255, 242, 0, 255)
        );
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

      // If debug
      final data = await rootBundle.load("assets/test_image.jpeg");
      // If not debug
      final picture = await _controller.takePicture();
      final bytes = await File(picture.path).readAsBytes();
      img.Image inputImage = debug ? img.decodeImage(data.buffer.asUint8List())! : img.decodeImage(bytes)!;

      final processedImage = await _processImage(inputImage);

      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DetectionPreviewScreen(
            image: processedImage,
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
        ]
      )
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
              padding: EdgeInsets.fromLTRB(15, 40, 0, 0),
              child: Text('Decklist Scanner'),
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
  final img.Image image;
  final List<String> detections;

  const DetectionPreviewScreen({super.key, required this.image, required this.detections});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      // TODO: Make this zoom to whole viewcreen.
      body: Center(
        child: InteractiveViewer(child: Image.memory(img.encodePng(image)))
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
              child: ListView(
                children: [
                  DataTable(
                      columns: [
                        DataColumn(label: Text("Deck Name", style: dataColumnStyle)),
                        DataColumn(label: Text("Colors", style: dataColumnStyle)),
                        DataColumn(label: Text("Date", style: dataColumnStyle)),
                      ],
                      rows: [
                        ...generateDataRows(decks, context)
                      ]
                  )
                ],
              )
            )
          );
        }
      }
    );
  }

  List<DataRow> generateDataRows(List<models.Deck>? decks, context) {

    final TextStyle dateColumnStyle = TextStyle(
      color: Colors.grey.withAlpha(255),
      fontStyle: FontStyle.italic
    );

    var dataRowList = decks?.map((deck) {
      return DataRow(
        cells: [DataCell(GestureDetector(
          onTap: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => DecklistViewer(deckId: deck.id))
            );
          },
          child: Text(deck.name),
        )),
        DataCell(Row(
          children: [
            for (String color in deck.colors.split(""))
              SvgPicture.asset(
                "assets/svg_icons/$color.svg",
                height: 14,
              )
          ],
        )),
        DataCell(Text(convertDatetimeToString(deck.dateTime), style: dateColumnStyle))
      ]);
    }).toList();
    if (dataRowList != null) {
      return dataRowList;
    } else {
      return [];
    }
  }
}

class DecklistViewer extends StatefulWidget {
  final int deckId;
  const DecklistViewer({super.key, required this.deckId});

  @override
  DecklistViewerState createState() => DecklistViewerState(deckId);
}

class DecklistViewerState extends State<DecklistViewer> {
  final int deckId;
  late Future<List<models.Deck>> decksFuture;
  DecklistViewerState(this.deckId);
  late List<String> renderValues = ["text", "type", "cmc"];

  @override
  void initState() {
    super.initState();
    decksFuture = _deckStorage.getAllDecks();
  }

  @override
  Widget build(BuildContext context) {
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
              // margin: EdgeInsets.fromLTRB(50, 25, 50, 25),
              alignment: Alignment.topCenter,
              child: ListView(
                padding: EdgeInsets.all(10),
                children: [
                  Row(
                    spacing: 5,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownMenu(
                        width: 0.3 * MediaQuery.of(context).size.width,
                        label: Text("Display"),
                        initialSelection: "text",
                        inputDecorationTheme: createDropdownStyling(),
                        textStyle: TextStyle(fontSize: 12),
                        dropdownMenuEntries: [
                          DropdownMenuEntry(value: "text", label: "Text"),
                          DropdownMenuEntry(value: "image", label: "Images")
                        ],
                        onSelected: (value) {
                          renderValues[0] = value!;
                          setState(() {});
                        },
                      ),
                      DropdownMenu(
                        width: 0.3 * MediaQuery.of(context).size.width,
                        label: Text("Group By"),
                        initialSelection: "type",
                        inputDecorationTheme: createDropdownStyling(),
                        textStyle: TextStyle(fontSize: 12),
                        dropdownMenuEntries: [
                          DropdownMenuEntry(value: "type", label: "Type"),
                          DropdownMenuEntry(value: "color", label: "Color")
                        ],
                        onSelected: (value) {
                          renderValues[1] = value!;
                          setState(() {});
                        },
                      ),
                      DropdownMenu(
                        width: 0.3 * MediaQuery.of(context).size.width,
                        label: Text("Sort By"),
                        initialSelection: "cmc",
                        inputDecorationTheme: createDropdownStyling(),
                        textStyle: TextStyle(fontSize: 12),
                        dropdownMenuEntries: [
                          DropdownMenuEntry(value: "cmc", label: "CMC"),
                          DropdownMenuEntry(value: "name", label: "Name")
                        ],
                        onSelected: (value) {
                          renderValues[2] = value!;
                          setState(() {});
                        },
                      ),
                    ]
                  ),
                  Divider(height: 30),
                  ...generateDeckView(deck!, renderValues)
                ],
              ),
            )
          );
        }
      }
    );
  }

  List<Widget> generateDeckView(models.Deck deck, List<String> renderValues) {
    // Initial setup for rendering
    final List<Widget> deckView = [];
    final headerStyle = TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.underline
    );

    var renderCard = (renderValues[0] == "text") ? createTextCard : createVisualCard;
    var rows = (renderValues[0] == "text") ? 1 : 2;

    final groupingAttribute = renderValues[1];
    final getAttribute = (groupingAttribute == "type")
        ? (card) => card.type
        : (card) => card.color();
    final uniqueGroupings = (groupingAttribute == "type") ? models.typeOrder : models.colorOrder;

    for (String attribute in uniqueGroupings) {

      List<Widget> header = [Container(padding: EdgeInsets.fromLTRB(0,20,0,5), child: Text(attribute, style: headerStyle))];

      // Sort by mana cost, updated to dynamic
      if (renderValues[2] == "name") {
        deck.cards.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else {
        deck.cards.sort((a, b) => a.manaValue - b.manaValue);
      }

      List<Widget> cardWidgets = deck.cards
        .where((card) => getAttribute(card) == attribute)
        .map((card) => renderCard(card))
        .toList();

      List<Widget> typeList = [];
      List<Widget> rowChildren = [];
      for (int i=0; i < cardWidgets.length; i++) {
        rowChildren.add(Container(
          width: (0.94 / rows) * MediaQuery.of(context).size.width,
          child: cardWidgets[i]
        ));
        if (((i + 1) % rows == 0) || (i == cardWidgets.length - 1)) {
          typeList.add(Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: rowChildren,
          ));
          rowChildren = [];
        }
      }

      if (cardWidgets.isNotEmpty) {
        deckView.add(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: header + typeList
        ));
      }
    }
    return deckView;
  }

  Widget createTextCard(models.Card card) {
    return Row(
      spacing: 8,
      children: [
        Text(
          card.title,
          style: TextStyle(
              fontSize: 16,
              height: 1.5
          ),
        ),
        card.createManaCost()
      ],
    );
  }

  Widget createVisualCard(models.Card card) {
    return Container(
      padding: EdgeInsets.all(2),
        child: FittedBox(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Image.network(card.imageUri!),
          )
        )    
    );
  }

  InputDecorationTheme createDropdownStyling() {
    return InputDecorationTheme(
      labelStyle: TextStyle(fontSize: 10),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: BoxConstraints.tight(
        const Size.fromHeight(40)
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
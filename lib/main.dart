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
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;

import 'utils/utils.dart';
import 'utils/data.dart';
import 'utils/models.dart' as models;
import 'download_screen.dart';

late CameraDescription _firstCamera;
late DeckStorage _deckStorage;

TextStyle _headerStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    decoration: TextDecoration.underline);

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
    _controller = CameraController(widget.camera,
        ResolutionPreset.ultraHigh // not ultra-high to possibly speed up app
        );
    _initializeControllerFuture = _controller.initialize();
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

      // If debug
      final data = await rootBundle.load("assets/test_image.jpeg");
      // If not debug
      final picture = await _controller.takePicture();
      final bytes = await File(picture.path).readAsBytes();
      img.Image inputImage = debug
          ? img.decodeImage(data.buffer.asUint8List())!
          : img.decodeImage(bytes)!;

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
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const MyDecksOverview()));
          },
        ),
        ListTile(
          title: const Text('Download Scryfall Data'),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const DownloadScreen()));
          },
        ),
      ],
    ));
  }
}

class DetectionPreviewScreen extends StatelessWidget {
  final img.Image image;
  final List<String> detections;

  const DetectionPreviewScreen(
      {super.key, required this.image, required this.detections});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      // TODO: Make this zoom to whole viewcreen.
      body: Center(
          child: InteractiveViewer(child: Image.memory(img.encodePng(image)))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    Center(child: CircularProgressIndicator()),
              ),
            );
            final deckId = await createDeckAndSave(detections);
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => DeckViewer(deckId: deckId),
                ),
                ModalRoute.withName('/'));
            // Make sure to adjust route to go back to 'My Decks'
          },
          label: Text("Save Deck"),
          icon: Icon(Icons.add)),
    );
  }

  Future<int> createDeckAndSave(List<String> detections) async {
    final allCards = await _deckStorage.getAllCards();
    final choices = allCards.map((card) => card.title).toList();
    final List<models.Card> matchedCards = [];
    debugPrint("Matching detections with database");
    for (final detection in detections) {
      final match = extractOne(query: detection, choices: choices);
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
                        DataTable(columns: [
                          DataColumn(
                              label: Text("Deck Name", style: dataColumnStyle)),
                          DataColumn(
                              label: Text("Colors", style: dataColumnStyle)),
                          DataColumn(
                              label: Text("Date", style: dataColumnStyle)),
                        ], rows: [
                          ...generateDataRows(decks, context)
                        ])
                      ],
                    )));
          }
        });
  }

  List<DataRow> generateDataRows(List<models.Deck>? decks, context) {
    final TextStyle dateColumnStyle = TextStyle(
        color: Colors.grey.withAlpha(255), fontStyle: FontStyle.italic);

    var dataRowList = decks?.map((deck) {
      return DataRow(cells: [
        DataCell(GestureDetector(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => DeckViewer(deckId: deck.id)));
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
        DataCell(Text(convertDatetimeToYMDHM(deck.dateTime),
            style: dateColumnStyle))
      ]);
    }).toList();
    if (dataRowList != null) {
      return dataRowList;
    } else {
      return [];
    }
  }
}

class DeckViewer extends StatefulWidget {
  final int deckId;
  const DeckViewer({super.key, required this.deckId});

  @override
  DeckViewerState createState() => DeckViewerState(deckId);
}

class DeckViewerState extends State<DeckViewer> {
  final int deckId;
  late Future<List<models.Deck>> decksFuture;
  DeckViewerState(this.deckId);
  List<String> renderValues = ["text", "type"];
  bool? showManaCurve = true;

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
            final deck = decks![deckId - 1];
            return Scaffold(
              appBar: AppBar(title: Text(deck.name)),
              body: Container(
                // margin: EdgeInsets.fromLTRB(50, 25, 50, 25),
                alignment: Alignment.topCenter,
                child: ListView(
                  padding: EdgeInsets.all(10),
                  children: [
                    Row(
                        spacing: 8,
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
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 2,
                            children: [
                              Text("Show Curve", style: TextStyle(height: 0.2, fontSize: 7)),
                              Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  value: showManaCurve,
                                  onChanged: (bool? value) {
                                    showManaCurve = value;
                                    setState(() {});
                                  }
                              ),
                            ],
                          )
                        ]
                    ),
                    Divider(height: 30),
                    if (showManaCurve!) ...generateManaCurve(deck.cards),
                    ...generateDeckView(deck, renderValues)
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton(
                heroTag: "Btn1",
                onPressed: () {
                  final controller = TextEditingController(text: deck.generateTextExport());
                  showDialog(
                      context: context,
                      builder: (context) => Dialog(
                          child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: TextFormField(
                                expands: true,
                                readOnly: true,
                                keyboardType: TextInputType.multiline,
                                maxLines: null,
                                minLines: null,
                                controller: controller,
                                onTap: () => controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.value.text.length),
                              ))));
                },
                child: const Icon(Icons.share),
              ),
            );
          }
        });
  }

  List<Widget> generateManaCurve(List<models.Card> cards) {
    List<Widget> outputChildren = [Text("Mana Curve", style: _headerStyle)];

    List<int> manaValues = [0, 1, 2, 3, 4, 5, 6, 7];
    final nonCreatureSeries = [];
    final creatureSeries = [];

    for (var val in manaValues) {
      condition(card) {
        if (val < 7) {
          return (card.manaValue == val);
        } else {
          return (card.manaValue > 6);
        }
      }

      nonCreatureSeries.add({
        "manaValue": (val < 7) ? val.toString() : "7+",
        "count": cards
            .where((card) => condition(card))
            .where((card) => card.type != "Creature")
            .length
      });
      creatureSeries.add({
        "manaValue": (val < 7) ? val.toString() : "7+",
        "count": cards
            .where((card) => condition(card))
            .where((card) => card.type == "Creature")
            .length
      });
    }

    List<charts.Series<dynamic, String>> seriesList = [
      charts.Series(
          id: "Non-Creature",
          domainFn: (datum, _) => datum["manaValue"],
          measureFn: (datum, _) => datum["count"],
          data: nonCreatureSeries),
      charts.Series(
          id: "Creature",
          domainFn: (datum, _) => datum["manaValue"],
          measureFn: (datum, _) => datum["count"],
          data: creatureSeries)
    ];

    outputChildren.add(SizedBox(
        height: 200,
        child: charts.BarChart(
            animate: false,
            seriesList,
            barGroupingType: charts.BarGroupingType.stacked,
            primaryMeasureAxis: charts.NumericAxisSpec(
                tickProviderSpec: charts.BasicNumericTickProviderSpec(
                    dataIsInWholeNumbers: true, desiredMinTickCount: 4)),
            behaviors: [charts.SeriesLegend()])));
    return outputChildren;
  }

  List<Widget> generateDeckView(models.Deck deck, List<String> renderValues) {
    // Initial setup for rendering
    final List<Widget> deckView = [];

    var renderCard =
        (renderValues[0] == "text") ? createTextCard : createVisualCard;
    var rows = (renderValues[0] == "text") ? 1 : 2;

    final groupingAttribute = renderValues[1];
    final getAttribute = (groupingAttribute == "type")
        ? (card) => card.type
        : (card) => card.color();
    final uniqueGroupings =
        (groupingAttribute == "type") ? models.typeOrder : models.colorOrder;

    for (String attribute in uniqueGroupings) {
      List<Widget> header = [
        Container(
            padding: EdgeInsets.fromLTRB(0, 20, 0, 5),
            child: Text(attribute, style: _headerStyle))
      ];

      List<Widget> cardWidgets = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .map((card) => renderCard(card))
          .toList();

      List<Widget> typeList = [];
      List<Widget> rowChildren = [];
      for (int i = 0; i < cardWidgets.length; i++) {
        rowChildren.add(SizedBox(
            width: (0.94 / rows) * MediaQuery.of(context).size.width,
            child: cardWidgets[i]));
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
            children: header + typeList));
      }
    }
    return deckView;
  }

  Widget createTextCard(models.Card card) {
    return Row(
      spacing: 8,
      children: [
        GestureDetector(
          onTap: () => showDialog(
              context: context,
              builder: (context) => Container(
                  padding: EdgeInsets.all(30), child: createVisualCard(card))),
          child: Text(
            card.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, height: 1.5),
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
        )));
  }

  InputDecorationTheme createDropdownStyling() {
    return InputDecorationTheme(
      labelStyle: TextStyle(fontSize: 10),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: BoxConstraints.tight(const Size.fromHeight(40)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

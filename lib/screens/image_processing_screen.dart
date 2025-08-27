import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card, Orientation;
import 'package:flutter/services.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'detection_preview.dart';
import '/utils/utils.dart';

import '/data/repositories/card_repository.dart';
import '/data/models/card.dart';
import '/models/detection.dart';

CardRepository cardRepository = CardRepository();

class deckImageProcessing extends StatefulWidget {
  final String filePath;
  const deckImageProcessing(
      {super.key, required this.filePath});

  @override
  _deckImageProcessingState createState() => _deckImageProcessingState(filePath);
}

class _deckImageProcessingState extends State<deckImageProcessing> {
  // Class inputs
  final String filePath;
  _deckImageProcessingState(this.filePath);

  late TextRecognizer _textRecognizer;
  late Future<void> _loadModelsFuture;
  late img.Image decodedImage;

  int ocrProgress = 0;
  int matchingProgress = 0;
  int orientationProgress = 0;
  int _numDetections = -1;
  int currentStep = 0;
  int totalSteps = 6;
  int? currentTaskCount;
  int? totalCurrentTask;
  String currentTask = "Loading image";
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadModelsFuture = _loadModels();

    // Start CardDetection after first layout complete
    WidgetsBinding.instance
      .addPostFrameCallback((_) {
        _runCardDetection().catchError((e) {
          debugPrint("Error: $e");
          setState(() {
            errorMessage = e.toString();
          });
        });
    });
  }

  Future<void> _loadModels() async {
    try {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    }
    catch (e) {
      setState(() {
        debugPrint("Error: $e");
        errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 50, vertical: 10),
          child: FutureBuilder(
            future: _loadModelsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return Column(
                  spacing: 25,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Spacer(flex: 7),
                    Text(
                      currentTask,
                      style: TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    CircularProgressIndicator(
                      value: currentTaskCount != null && totalCurrentTask != null
                        ? currentTaskCount! / totalCurrentTask!
                        : null,
                    ),
                    Text(currentTaskCount != null && totalCurrentTask != null
                        ? "$currentTaskCount/$totalCurrentTask"
                        : ""),
                    Spacer(flex: 1),
                    LinearProgressIndicator(
                        value: currentStep / totalSteps
                    ),
                    Text("Total Progress"),
                    if (errorMessage != null) ...[
                      Text("Error:", style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold
                      )),
                      Text(errorMessage ?? ""),
                    ],
                    Spacer(flex: 3,)
                  ]
                );
              }
              return const CircularProgressIndicator();
            }
          ),
        )
      )
    );
  }

  Future<void> _runCardDetection() async {
    // 1. Take picture (or load from disk)
    // 2. Run titleDetection
    // 3. for each detection: transcribeDetection
    // 4. Combine these into output image.

    // Yolo title detection

    // Since accelerometer orientation can be a bit flaky for pictures on a table,
    // we run title detection on all 4 orientations and take the one with the most
    // detections.

    img.Image inputImage = await compute(processInputImage, filePath);

    setState(() {
      currentTask = "Running title detection on image";
      currentStep += 1;
    });

    List<List<int>> detections = [];
    int correctRotation = 0;

    // TODO: Figure out how move this to isolate, currently causing errors if we do
    final modelPath = 'assets/20250522_fp16.tflite';
    final modelFile = await rootBundle.load(modelPath);
    final modelBuffer = modelFile.buffer.asUint8List();

    List<Future<List<List<int>>>> futureDetections = [0, 90, 180, 270].map((rot) {
      Uint8List detectionBytes = img.encodePng(img.copyRotate(inputImage, angle: rot));
      return compute(_titleDetection, {
        'inputBytes': detectionBytes,
        'modelBuffer': modelBuffer
      });
    }).toList();

    List<List<List<int>>> allDetections = await Future.wait(futureDetections);

    // Choose best orientation by number of detections
    int maxDetections = 0;
    for (int i=0; i < 4; i++) {
      if (allDetections[i].length > maxDetections) {
        detections = allDetections[i];
        maxDetections = detections.length;
        correctRotation = [0, 90, 180, 270][i];
      }
    }

    setState(() {
      currentTask = "Transcribing detections to text";
      currentStep += 1;
    });

    inputImage = img.copyRotate(inputImage, angle: correctRotation);
    img.Image inputImageCopy = inputImage.clone();


    // Using MLKit OCR to turn BBox info into strings.
    List<Future<String>> detectionTextFutures = detections
        .map((detection) => _transcribeDetection(detection, inputImage))
        .toList();

    _numDetections = detectionTextFutures.length;
    currentTaskCount = 0;
    totalCurrentTask = _numDetections;
    totalSteps = 3 * _numDetections;
    currentStep = _numDetections;

    // Update progress bar as each future completes
    for (var future in detectionTextFutures) {
      future.then((_) {
        debugPrint("Finished OCRing detection ${ocrProgress + 1}");
        setState(() {
          currentTaskCount = currentTaskCount! + 1;
          currentStep += 1;
        });
      });
    }

    List<String> detectionText = await Future.wait(detectionTextFutures);

    setState(() {
      currentTask = "Matching transcribed titles to card database";
      currentStep += 1;
    });

    final allCards = await cardRepository.getAllCards();
    List<String> choices = [];
    Map<int, int> choicesToCardsMap = {};
    final List<Future<ExtractedResult<String>>> matchedFutures = [];
    for (int i = 0; i < allCards.length; i++) {
      final cardName = allCards[i].name;
      // Two cards to add to choices
      if (cardName.contains(" // ")) {
        cardName.split(" // ").forEach((el) => choices.add(el));
        choicesToCardsMap[choices.length - 2] = i;
        choicesToCardsMap[choices.length - 1] = i;
      }
      // Single card to add
      else {
        choices.add(cardName);
        choicesToCardsMap[choices.length - 1] = i;
      }
    }

    debugPrint("Matching detections with database");
    currentTaskCount = 0;
    totalCurrentTask = _numDetections;


    for (final text in detectionText) {
      debugPrint("Matching $text with database");
      final matchParams = MatchParams(query: text, choices: choices);
      Future<ExtractedResult<String>> matchFuture = compute(runFuzzyMatch, matchParams);
      matchFuture.then((match) {
        setState(() {
          currentTaskCount = currentTaskCount! + 1;
          currentStep += 1;
        });
      });
      matchedFutures.add(matchFuture);
    }

    final matches = await Future.wait(matchedFutures);

    setState(() => currentStep += 1);

    List<Card?> matchedCards = matches.map(
            (match) => match.score > 5
                ? allCards[choicesToCardsMap[match.index]!]
                : null
    ).toList();

    // Add annotations to image
    img.Image outputImage = img.adjustColor(inputImage, brightness: 0.5);
    final overlayColor = img.ColorRgba8(255, 242, 0, 255);

    List<Detection> detectionOutput = [];

    for (var i = 0; i < detections.length; i++) {
      var [x1, y1, x2, y2] = detections[i];
      // Draw bounding box around detected title
      img.drawRect(
        outputImage,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: overlayColor,
        thickness: 5,
      );
      // Add text to image
      img.drawString(outputImage, matchedCards[i]?.name ?? "",
          font: img.arial48,
          x: x1,
          y: y1 - 55,  // Place text above box
          color: overlayColor
      );

      // Create output list
      detectionOutput.add(Detection(
        card: matchedCards[i],
        ocrText: detectionText[i],
        ocrDistance: matches[i].score,
        textImage: img.copyCrop(
          inputImageCopy,
          x: x1,
          y: y1,
          width: x2 - x1,
          height: y2 - y1
        )
      ));
    }

    // Add count of cards to image
    img.drawString(
      outputImage,
      "Total Cards: ${matchedCards.length}",
      font: img.arial48,
      x: outputImage.width - 400,
      y: outputImage.height - 150,
      color: overlayColor
    );

    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => DetectionPreviewScreen(
            image: outputImage, detections: detectionOutput),
      ),
      ModalRoute.withName('/')
    );
  }

  Future<String> _transcribeDetection(List<int> detection, img.Image inputImage) async {

    // Extract only relevant part from inputImage
    var [x1, y1, x2, y2] = detection;
    img.Image detectionImg = img.copyCrop(inputImage,
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1
    );

    // The OCR package fails on image with height < 32px. Here we resize titles
    // higher than 16px to 32px.
    if ((detectionImg.height < 32) && (detectionImg.height > 16)) {
      detectionImg = img.copyResize(detectionImg,
        height: 33,
        maintainAspect: true,
        interpolation: img.Interpolation.cubic
      );
    }

    // Convert img.Image to MLKit inputImage
    // TODO: Figure out how to do this in memory
    Directory tmpDir = await getTemporaryDirectory();
    File tmpFile = File('${tmpDir.path}/thumbnail_${x1}_${x2}_${y1}_${y2}.png');
    await img.encodeImageFile(tmpFile.path, detectionImg);
    final detectionImage = InputImage.fromFilePath(tmpFile.path);
    // final detectionImage = InputImage.fromBytes(
    //     bytes: detectionImg.getBytes(order: img.ChannelOrder.bgra),
    //     metadata: InputImageMetadata(
    //         size: Size(detectionImg.width.toDouble(), detectionImg.height.toDouble()),
    //         rotation: InputImageRotation.rotation0deg,
    //         format: InputImageFormat.bgra8888,
    //         bytesPerRow: 4 * detectionImg.width
    //     )
    // );

    // Run MLKit text recognition
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(detectionImage);
      debugPrint("Text: ${recognizedText.text}");
      return recognizedText.text;
    }
    catch (e) {
      // When OCR fails (ie < 32px), for we'll return the current NaN, empty string
      return "";
    }
  }
}

Future<img.Image> processInputImage(String fp) async {
  // Try reading file until it exists
  int i = 0;
  while (!File(fp).existsSync()) {
    i++;
    debugPrint("Attempt to read image file $i");
    await Future.delayed(Duration(milliseconds: 100));
  }
  Uint8List fileBytes = await File(fp).readAsBytes();
  final decodedImage = img.decodeImage(fileBytes)!;
  debugPrint("Loaded image dimensions: ${decodedImage.width}x${decodedImage.height}");
  return decodedImage;
}

Future<List<List<int>>> _titleDetection(Map argMap) async {
  final double detectionThreshold = 0.5;
  final inputBytes = argMap['inputBytes'];
  final modelBuffer = argMap['modelBuffer'];

  final detector = Interpreter.fromBuffer(modelBuffer);
  final inputImage = img.decodePng(inputBytes)!;

  // Getting input/output shapes
  final input = detector.getInputTensor(0); // BWHC
  final output = detector.getOutputTensor(0); // BXYXYC
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
  detector.run(inputTensor, outputTensor);
  detector.close();

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
  ]).toList();

  return detections;
}

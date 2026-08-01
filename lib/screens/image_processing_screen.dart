import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card, Orientation;
import 'package:flutter/services.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_litert/flutter_litert.dart' hide Detection;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'detection_preview.dart';
import '/utils/utils.dart';

import '/data/repositories/card_repository.dart';
import '/data/models/card.dart';
import '/data/models/deck.dart';
import '/data/models/deck_upsert.dart';
import '/models/detection.dart';

CardRepository cardRepository = CardRepository();

class deckImageProcessing extends StatefulWidget {
  final String filePath;
  final CaptureSource captureSource;
  final DeckUpsert? baseDeck;
  final img.Image? baseDeckImage;
  final bool isSideboardStep;
  final DeckUpsert? prefill;
  final void Function(Deck)? onDeckSaved;
  const deckImageProcessing(
      {super.key,
      required this.filePath,
      this.captureSource = CaptureSource.gallery,
      this.baseDeck,
      this.baseDeckImage,
      this.isSideboardStep = false,
      this.prefill,
      this.onDeckSaved});

  @override
  _deckImageProcessingState createState() => _deckImageProcessingState();
}

class _deckImageProcessingState extends State<deckImageProcessing> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    } catch (e) {
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
                      value:
                          currentTaskCount != null && totalCurrentTask != null
                              ? currentTaskCount! / totalCurrentTask!
                              : null,
                    ),
                    Text(currentTaskCount != null && totalCurrentTask != null
                        ? "$currentTaskCount/$totalCurrentTask"
                        : ""),
                    Spacer(flex: 1),
                    LinearProgressIndicator(value: currentStep / totalSteps),
                    Text("Total Progress"),
                    if (errorMessage != null) ...[
                      Text("Error:",
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text(errorMessage ?? ""),
                    ],
                    Spacer(
                      flex: 3,
                    )
                  ]);
            }
            return const CircularProgressIndicator();
          }),
    )));
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

    img.Image inputImage = await compute(processInputImage, widget.filePath);

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

    final pngBytes = img.encodePng(inputImage);

    final allDetections = await compute(_runAllOrientations, {
      'encodedImage': pngBytes,
      'modelBuffer': modelBuffer,
      'rotations': [0, 90, 180, 270],
    });

    // Choose best orientation by number of detections
    int maxDetections = 0;
    for (int i = 0; i < 4; i++) {
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

    final cardNames = await cardRepository.getAllCardNames();
    List<String> choices = [];
    final List<Future<ExtractedResult<String>>> matchedFutures = [];
    for (int i = 0; i < cardNames.length; i++) {
      final name = cardNames[i]['name']!;
      if (name.contains(" // ")) {
        name.split(" // ").forEach((el) => choices.add(el));
      } else {
        choices.add(name);
      }
    }

    debugPrint("Matching detections with database");
    currentTaskCount = 0;
    totalCurrentTask = _numDetections;

    for (final text in detectionText) {
      debugPrint("Matching $text with database");
      final matchParams = MatchParams(query: text, choices: choices);
      Future<ExtractedResult<String>> matchFuture =
          compute(runFuzzyMatch, matchParams);
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

    List<Card?> matchedCards = [];
    for (final match in matches) {
      if (match.score <= 5) {
        matchedCards.add(null);
        continue;
      }
      final card = await cardRepository.getCardByName(choices[match.index]);
      matchedCards.add(card);
    }

    img.Image outputImage = img.adjustColor(inputImage, brightness: 0.5);

    List<Detection> detectionOutput = [];

    for (var i = 0; i < detections.length; i++) {
      var [x1, y1, x2, y2] = detections[i];

      final score = matches[i].score;
      final color = matchedCards[i] == null
          ? img.ColorRgba8(158, 158, 158, 255)
          : score > 70
              ? img.ColorRgba8(76, 175, 80, 255)
              : score > 40
                  ? img.ColorRgba8(255, 193, 7, 255)
                  : img.ColorRgba8(244, 67, 54, 255);

      img.drawRect(outputImage,
          x1: x1, y1: y1, x2: x2, y2: y2,
          color: color, thickness: 5);

      img.drawString(outputImage, matchedCards[i]?.name ?? "",
          font: img.arial48, x: x1, y: y1 - 55, color: color);

      detectionOutput.add(Detection(
          card: matchedCards[i],
          ocrText: detectionText[i],
          ocrDistance: matches[i].score,
          textImage: img.copyCrop(inputImageCopy,
              x: x1, y: y1, width: x2 - x1, height: y2 - y1),
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2));
    }

    img.drawString(outputImage, "Total Cards: ${matchedCards.length}",
        font: img.arial48,
        x: outputImage.width - 400,
        y: outputImage.height - 150,
        color: img.ColorRgba8(255, 242, 0, 255));

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DetectionPreviewScreen(
          image: outputImage,
          originalImage: inputImageCopy,
          detections: detectionOutput,
          captureSource: widget.captureSource,
          baseDeck: widget.baseDeck,
          baseDeckImage: widget.baseDeckImage,
          isSideboardStep: widget.isSideboardStep,
          prefill: widget.prefill,
          onDeckSaved: widget.onDeckSaved,
        ),
      ),
    );
  }

  Future<String> _transcribeDetection(
      List<int> detection, img.Image inputImage) async {
    // Extract only relevant part from inputImage
    var [x1, y1, x2, y2] = detection;
    img.Image detectionImg =
        img.copyCrop(inputImage, x: x1, y: y1, width: x2 - x1, height: y2 - y1);

    // The OCR package fails on image with height < 32px. Here we resize titles
    // higher than 16px to 32px.
    if ((detectionImg.height < 32) && (detectionImg.height > 16)) {
      detectionImg = img.copyResize(detectionImg,
          height: 33,
          maintainAspect: true,
          interpolation: img.Interpolation.cubic);
    }

    // Convert img.Image to MLKit inputImage in memory
    final detectionImage = InputImage.fromBitmap(
      bitmap: detectionImg.getBytes(order: img.ChannelOrder.rgba),
      width: detectionImg.width,
      height: detectionImg.height,
    );

    // Run MLKit text recognition
    try {
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(detectionImage);
      debugPrint("Text: ${recognizedText.text}");
      return recognizedText.text;
    } catch (e) {
      // When OCR fails (ie < 32px), for we'll return the current NaN, empty string
      return "";
    }
  }
}

Future<img.Image> processInputImage(String fp) async {
  Uint8List fileBytes = await File(fp).readAsBytes();
  final decodedImage = img.decodeImage(fileBytes)!;
  debugPrint(
      "Loaded image dimensions: ${decodedImage.width}x${decodedImage.height}");
  return decodedImage;
}

Future<List<List<List<int>>>> _runAllOrientations(Map argMap) async {
  final Uint8List encodedImage = argMap['encodedImage'];
  final Uint8List modelBuffer = argMap['modelBuffer'];
  final List<int> rotations = argMap['rotations'];
  final double detectionThreshold = 0.5;

  final inputImage = img.decodePng(encodedImage)!;
  final detector = Interpreter.fromBuffer(modelBuffer);

  final input = detector.getInputTensor(0);
  final output = detector.getOutputTensor(0);
  final int inputH = input.shape[1];
  final int inputW = input.shape[2];

  final allDetections = <List<List<int>>>[];

  for (final rot in rotations) {
    final rotated = img.copyRotate(inputImage, angle: rot);

    final resizedImage = img.copyResize(
      rotated,
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

    detector.run(inputTensor, outputTensor);

    bool isPortrait = rotated.width < rotated.height;
    int scalingFactor = isPortrait ? rotated.height : rotated.width;
    double widthPadding =
        isPortrait ? (rotated.height - rotated.width) / 2 : 0.0;
    double heightPadding =
        !isPortrait ? (rotated.width - rotated.height) / 2 : 0.0;

    List<List<int>> detections = (outputTensor[0] as List<List<double>>)
        .where((element) => (element[4] > detectionThreshold))
        .map((el) => [
              (el[0] * scalingFactor - widthPadding).toInt(),
              (el[1] * scalingFactor - heightPadding).toInt(),
              (el[2] * scalingFactor - widthPadding).toInt(),
              (el[3] * scalingFactor - heightPadding).toInt()
            ])
        .toList();

    allDetections.add(detections);
  }

  detector.close();
  return allDetections;
}

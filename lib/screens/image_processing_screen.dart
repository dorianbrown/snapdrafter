import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:fuzzywuzzy/model/extracted_result.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'detection_preview.dart';
import '/utils/data.dart';
import '/utils/utils.dart';
import '/utils/models.dart';

DeckStorage _deckStorage = DeckStorage();

class deckImageProcessing extends StatefulWidget {
  final img.Image? inputImage;
  final String? filePath;
  const deckImageProcessing({super.key, this.inputImage, this.filePath});

  @override
  _deckImageProcessingState createState() => _deckImageProcessingState(inputImage, filePath);
}

class _deckImageProcessingState extends State<deckImageProcessing> {
  // Class inputs
  final img.Image? inputImage;
  final String? filePath;
  _deckImageProcessingState(this.inputImage, this.filePath);

  late Interpreter _detector;
  late TextRecognizer _textRecognizer;
  late Future<void> _loadModelsFuture;
  late img.Image decodedImage;

  bool detectionStarted = false;
  int ocrProgress = 0;
  int matchingProgress = 0;
  int _numDetections = -1;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadModelsFuture = _loadModels();
    final processInputFuture = processInputImage();
    Future.wait([_loadModelsFuture, processInputFuture]).then((_) {
      _runCardDetection(decodedImage);
      setState(() {
        detectionStarted = true;
      });
    });
  }

  Future processInputImage() async {
    if (inputImage != null) {
      decodedImage = inputImage!;
    } else {
      // Try reading file until it exists
      int i=0;
      while (!File(filePath!).existsSync()) {
        i++;
        debugPrint("Attempt to read image file $i");
        await Future.delayed(Duration(milliseconds: 100));
      }
      Uint8List fileBytes = await File(filePath!).readAsBytes();
      decodedImage = img.decodeJpg(fileBytes)!;
      debugPrint("Loaded image dimensions: ${decodedImage.width}x${decodedImage.height}");
    }
  }

  Future<void> _loadModels() async {
    try {
      final options = InterpreterOptions();
      if (Platform.isAndroid) {
        // options.addDelegate(GpuDelegateV2());
      }
      final modelPath = 'assets/run22_fp16.tflite';
      _detector = await Interpreter.fromAsset(modelPath, options: options);
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      setState(() {});
    } catch (e) {
      debugPrint('Error loading models: $e');
    }
  }

  @override
  void dispose() {
    _detector.close();
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
                      if (!detectionStarted) ...[
                        Text("Loading image..."),
                        SizedBox(height: 100),
                        CircularProgressIndicator()
                      ] else ...[
                        Spacer(flex: 4,),
                        Text("Recognizing text in titles..."),
                        LinearProgressIndicator(
                            value: _numDetections > 0
                                ? ocrProgress / _numDetections
                                : 0
                        ),
                        Text("Progress: $ocrProgress / $_numDetections"),
                        Spacer(flex: 1,),
                        Text("Matching OCR to cards database..."),
                        LinearProgressIndicator(
                            value: _numDetections > 0
                                ? matchingProgress / _numDetections
                                : 0
                        ),
                        Text("Progress: $matchingProgress / $_numDetections"),
                        if (errorMessage != null)
                          Text("Error:", style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold
                          )),
                        Text(errorMessage ?? ""),
                        Spacer(flex: 3,)
                      ]
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

  Future<void> _runCardDetection(img.Image inputImage) async {
    // 1. Take picture (or load from disk)
    // 2. Run titleDetection
    // 3. for each detection: transcribeDetection
    // 4. Combine these into output image.

    final img.Image inputImageCopy = inputImage.clone();

    // Yolo title detection
    List<List<int>> detections = _titleDetection(inputImage);

    // Using MLKit OCR to turn BBox info into strings.
    List<Future<String>> detectionTextFutures = detections
        .map((detection) => _transcribeDetection(detection, inputImage))
        .toList();

    _numDetections = detectionTextFutures.length;

    // Update progress bar as each future completes
    for (var future in detectionTextFutures) {
      future.then((_) {
        debugPrint("Finished OCRing detection ${ocrProgress + 1}");
        setState(() => ocrProgress = ocrProgress + 1);
      });
    }

    List<String> detectionText = await Future.wait(detectionTextFutures);

    final allCards = await _deckStorage.getAllCards();
    final choices = allCards.map((card) => card.title).toList();
    final List<Future<ExtractedResult<String>>> matchedFutures = [];
    debugPrint("Matching detections with database");
    for (final text in detectionText) {
      debugPrint("Matching $text with database");
      final matchParams = MatchParams(query: text, choices: choices);
      Future<ExtractedResult<String>> matchFuture = compute(runFuzzyMatch, matchParams);
      matchFuture.then((match) {
        setState(() => matchingProgress = matchingProgress + 1);
      });
      matchedFutures.add(matchFuture);
    }

    final matches = await Future.wait(matchedFutures);
    List<Card> matchedCards = matches.map((match) => allCards[match.index]).toList();

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
      img.drawString(outputImage, matchedCards[i].name,
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
    final RecognizedText recognizedText = await _textRecognizer.processImage(detectionImage);
    debugPrint("Text: ${recognizedText.text}");
    return recognizedText.text;
  }
}
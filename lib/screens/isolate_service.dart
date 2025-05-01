import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:hello_world/screens/deck_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'recognition.dart'; // Recognition data structure
import '../utils/image.dart';

class IsolateService {
  static late Interpreter _interpreter;
  static late List<int> _inputShape;
  // Output details - adjust based on your model
  static late List<int> _outputShape;
  static late int _inputW;
  static late int _inputH;
  static const double CONFIDENCE_THRESHOLD = 0.3; // Minimum score threshold

  // Isolate entry point
  static void entryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    // Send the isolate's SendPort back to the main thread
    mainSendPort.send(isolateReceivePort.sendPort);
    debugPrint("Isolate started, sending SendPort back.");

    // Listen for messages from the main thread
    isolateReceivePort.listen((dynamic message) async {
      if (message is Map && message['action'] == 'init') {
        debugPrint("Isolate received init message.");
        await _loadModelAndLabels(message['modelBuffer']);
        debugPrint("Isolate model loaded.");
        // Optionally confirm back to main thread if needed
      } else if (message is IsolateData) {
        // Process the camera frame
        try {
          final results = await _runInference(message);
          // Send results back to the main thread
          mainSendPort.send(results);
        } catch (e, stacktrace) {
          debugPrint("Error in isolate inference: $e\n$stacktrace");
          // Optionally send an error message back
          // mainSendPort.send('error');
        }
      } else {
        debugPrint("Isolate received unknown message: $message");
      }
    });
  }

  static Future<void> _loadModelAndLabels(Uint8List modelBuffer) async {

    // Interpreter configuration
    final interpreterOptions = InterpreterOptions();

    try {
      interpreterOptions.addDelegate(GpuDelegateV2());
    } catch (e) {
      debugPrint("GPU delegate not available: $e");
    }

    // Load model
    _interpreter = Interpreter.fromBuffer(
      modelBuffer,
      options: interpreterOptions
    );
    debugPrint('Interpreter loaded successfully');

    final inputTensor = _interpreter.getInputTensor(0); // BWHC
    _inputShape = inputTensor.shape; // e.g., [1, 300, 300, 3]
    _inputW = _inputShape[1];
    _inputH = _inputShape[2];

    final outputTensor = _interpreter.getOutputTensor(0); // BXYXYC

    _outputShape = outputTensor.shape;

    debugPrint('Input Shape: $_inputShape');
    debugPrint('Output Shape:$_outputShape');
  }

  // Main inference function
  static Future<List<Recognition>> _runInference(IsolateData data) async {

    final watch = Stopwatch();
    watch.start();

    // 1. Preprocess the image (YUV to RGB, Resize, Normalize)
    final img.Image? preprocessedImage = _preprocessImage(data);
    debugPrint("Preprocessing took ${watch.elapsedMilliseconds} ms");
    watch.reset();
    if (preprocessedImage == null) {
      return [];
    }

    // 2. Define Output Buffers
    // Adjust sizes and types based on your model's output tensors

    // Filling input tensor with image data
    final input = List<double>
        .filled(_inputShape.reduce((a, b) => a * b), 0)
        .reshape(_inputShape);

    final output = List<double>
        .filled(_outputShape.reduce((a, b) => a * b), 0)
        .reshape(_outputShape);

    for (int y = 0; y < _inputH; y++) {
      for (int x = 0; x < _inputW; x++) {
        final pixel = preprocessedImage.getPixel(x, y);
        input[0][y][x][0] = pixel.r / 255.0;
        input[0][y][x][1] = pixel.g / 255.0;
        input[0][y][x][2] = pixel.b / 255.0;
      }
    }
    debugPrint("Tensor creation took ${watch.elapsedMilliseconds} ms");
    watch.reset();

    // 3. Run Inference
    _interpreter.run(input, output);
    debugPrint("Inference took ${watch.elapsedMilliseconds} ms");
    watch.reset();

    // 4. Postprocess Results
    final List<Recognition> recognitions = _postProcessResults(output, data.height, data.width);
    debugPrint("Postprocessing took ${watch.elapsedMilliseconds} ms");

    return recognitions;
  }

  static img.Image? _preprocessImage(IsolateData data) {

    // Take raw stream data and convert into img.Image to make resizing easier
    img.Image rgbImage = convertYuvToRgb(data.planes, data.width, data.height, data.bytesPerRow);

    debugPrint("Input dimensions: ${rgbImage.width} x ${rgbImage.height}");

    // Resize the image to the model's input size
    final resizedImage = img.copyResize(
      rgbImage,
      width: _inputW,
      height: _inputH,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(0, 0, 0, 255),
    );

    return img.copyRotate(resizedImage, angle: 90);
  }

  static List<Recognition> _postProcessResults(List outputs, int inputW, int inputH) {
    final List<Recognition> recognitions = [];

    // Converting output detection dimensions back to full
    // image dimensions
    // Since we used preserve aspect ratio, we need padding to properly convert
    // back to original image dimensions
    bool isPortrait = inputW < inputH;
    int scalingFactor = isPortrait ? inputH : inputW;
    double widthPadding = isPortrait ? (inputH - inputW) / 2 : 0.0;
    double heightPadding = !isPortrait ? (inputW - inputH) / 2 : 0.0;

    for (int i = 0; i < outputs[0].length; i++) {
      final List<double> detection = outputs[0][i];
      final score = detection[4];

      if (score > CONFIDENCE_THRESHOLD) {
        // Get bounding box coordinates (normalized [0.0, 1.0])
        // Scaled back to full image dimensions
        final x1 = (detection[0] * scalingFactor - widthPadding);
        final y1 = (detection[1] * scalingFactor - heightPadding);
        final x2 = (detection[2] * scalingFactor - widthPadding);
        final y2 = (detection[3] * scalingFactor - heightPadding);

        recognitions.add(
          Recognition(
            id: i,
            score: score,
            location: Rect.fromLTRB(x1, y1, x2, y2),
          ),
        );
      }
    }

    debugPrint("Num Detections: ${recognitions.length}");

    return recognitions;
  }

}
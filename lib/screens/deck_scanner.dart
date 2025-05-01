import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart'; // For Interpreter

import 'isolate_service.dart'; // We'll create this file next
import 'recognition.dart'; // Data structure for results
import 'box_widget.dart'; // Widget to draw boxes

class RealtimeObjectDetection extends StatefulWidget {
  @override
  _RealtimeObjectDetectionState createState() => _RealtimeObjectDetectionState();
}

class _RealtimeObjectDetectionState extends State<RealtimeObjectDetection> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  List<Recognition>? _recognitions;
  Size? _previewSize; // Size of the camera preview widget
  late Uint8List modelBuffer;

  // Isolate communication
  Isolate? _isolate;
  final ReceivePort _receivePort = ReceivePort(); // Receives messages FROM isolate
  SendPort? _sendPort; // Sends messages TO isolate

  @override
  void initState() {
    super.initState();
    loadModelBuffer();
    WidgetsBinding.instance.addObserver(this);
    _initializeCameraAndIsolate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopProcessing();
    _cameraController?.dispose();
    super.dispose();
  }

  void loadModelBuffer() async {
    await rootBundle.load('assets/run22_fp16.tflite').then((rawAsset) {
      modelBuffer = rawAsset.buffer.asUint8List();
    }).catchError((e) {
      debugPrint("Error loading model buffer: $e");
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Stop camera and processing when app is inactive or paused
      _stopProcessing();
      cameraController.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      // Resume camera and processing when app resumes
      _initializeCameraAndIsolate(); // Re-initialize if needed or just start stream
    }
  }

  Future<void> _initializeCameraAndIsolate() async {
    // Start Isolate
    await _startIsolate();

    // Initialize Camera
    final cameras = await availableCameras();
    // Use the back camera if available, otherwise the first one
    final camera = cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first);

    _cameraController = CameraController(
      camera,
      ResolutionPreset.veryHigh, // Adjust resolution as needed for performance
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Common format
    );

    try {
      await _cameraController!.initialize();
      _previewSize = _cameraController!.value.previewSize; // Get preview size

      // Listen for results from the isolate
      _receivePort.listen(_handleIsolateMessage);

      // Start the image stream
      await _cameraController!.startImageStream(_processCameraImage);
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      print('Error initializing camera: $e');
      // Handle error appropriately
    }
  }

  Future<void> _startIsolate() async {
    // Spawn the isolate
    _isolate = await Isolate.spawn(
      IsolateService.entryPoint, // The static entry point function
      _receivePort.sendPort, // Send the main receive port to the isolate
    );
  }

  void _stopProcessing() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort.close(); // Close the port
    _isProcessingFrame = false; // Ensure no more frames are sent
  }


  void _handleIsolateMessage(dynamic data) {
    if (data is SendPort) {
      // First message from isolate is its SendPort
      _sendPort = data;
      debugPrint("Main received isolate SendPort");
      // Optionally send model/label paths now if not hardcoded in isolate
      _sendPort?.send({
        'action': 'init',
        'modelBuffer': modelBuffer,
      });

    } else if (data is List<Recognition>) {
      // Subsequent messages are detection results
      if (mounted) { // Check if widget is still in the tree
        setState(() {
          _recognitions = data;
        });
      }
      _isProcessingFrame = false; // Ready for the next frame
    } else {
      debugPrint("Main received unknown message: $data");
      _isProcessingFrame = false; // Unblock processing
    }
  }

  void _processCameraImage(CameraImage cameraImage) {
    if (_sendPort == null || _isProcessingFrame) {
      // Don't send if isolate isn't ready or is busy
      return;
    }

    _isProcessingFrame = true; // Mark as busy

    // Prepare data for the isolate
    // CameraImage is not directly transferable, extract necessary data
    final isolateData = IsolateData(
      cameraImage.planes.map((plane) => plane.bytes).toList(),
      cameraImage.height,
      cameraImage.width,
      cameraImage.planes.map((plane) => plane.bytesPerRow).toList(), // Pass bytesPerRow
      // You might need camera sensor orientation for correct rotation
      // _cameraController?.description.sensorOrientation ?? 0
    );

    // Send data to the isolate
    _sendPort!.send(isolateData);
  }


  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Object Detection')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Calculate the scale factor to map camera preview coords to screen coords
    // This might need adjustments based on BoxFit and screen rotation
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    // Preview size is usually landscape, device is portrait. Handle rotation if needed.
    final previewW = _previewSize?.height ?? screenW; // Swapped for portrait preview
    final previewH = _previewSize?.width ?? screenH; // Swapped for portrait preview

    // This scaling assumes BoxFit.cover and portrait orientation.
    // It might need refinement depending on your specific layout and rotation handling.
    double scaleW = screenW / previewW;
    double scaleH = screenH / previewH;
    // Choose the larger scale factor to ensure the preview covers the screen (like BoxFit.cover)
    double scale = scaleW > scaleH ? scaleW : scaleH;

    debugPrint("Screen size: $screenW x $screenH");
    debugPrint("Preview size: $previewW x $previewH");

    return Scaffold(
      appBar: AppBar(title: Text('Realtime Object Detection')),
      body: Stack(
        children: [
          Container(
            width: screenW,
            child: FittedBox(
                fit: BoxFit.fitWidth,
                child: Container(
                  width: 100,
                  child: AspectRatio(
                    aspectRatio: 1/_cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                )
            ),
          ),
          // Bounding Boxes using CustomPaint or dedicated widget
          BoundingBoxWidget(
            results: _recognitions ?? [],
            previewH: previewH, // Use dimensions of the *image* input to model
            previewW: previewW, // Use dimensions of the *image* input to model
            screenH: screenH, // Actual screen height
            screenW: screenW, // Actual screen width
            scale: scale * 0.8, // Pass the calculated scale
          ),
        ],
      ),
    );
  }
}

// Helper class to package data for the isolate
class IsolateData {
  final List<Uint8List> planes;
  final int height;
  final int width;
  final List<int> bytesPerRow; // Add this

  IsolateData(this.planes, this.height, this.width, this.bytesPerRow);
}
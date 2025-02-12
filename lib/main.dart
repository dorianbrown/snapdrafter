import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:tflite_flutter/tflite_flutter.dart';

Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  WidgetsFlutterBinding.ensureInitialized();

  // Obtain a list of the available cameras on the device.
  final cameras = await availableCameras();

  // Get a specific camera from the list of available cameras.
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(
        // Pass the appropriate camera to the TakePictureScreen widget.
        camera: firstCamera,
      ),
    ),
  );
}

// A screen that allows users to take a picture using a given camera.
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    super.key,
    required this.camera,
  });

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
      // Get a specific camera from the list of available cameras.
      widget.camera,
      // Define the resolution to use.
      ResolutionPreset.high,
    );

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      // You must wait until the controller is initialized before displaying the
      // camera preview. Use a FutureBuilder to display a loading spinner until the
      // controller has finished initializing.
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return CameraPreview(_controller);
          } else {
            // Otherwise, display a loading indicator.
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        // Provide an onPressed callback.
        onPressed: () async {
          // Take the Picture in a try / catch block. If anything goes wrong,
          // catch the error.
          try {
            // Ensure that the camera is initialized.
            await _initializeControllerFuture;

            // Attempt to take a picture and get the file `image`
            // where it was saved.
            final picture = await _controller.takePicture();
            final test_image = "assets/test_image.jpeg";

            final bytes = await File(test_image).readAsBytes();
            final img.Image image = img.decodeImage(bytes)!;
            
            img.Image resized_image = img.copyResize(
                image,
                width: 1024,
                height: 1024,
                maintainAspect: true
            );

            final input_tensor = List<double>.filled(1024*1024*3, 0).reshape([1, 1024, 1024, 3]);
            final output_tensor = List<double>.filled(5*21504, -1).reshape([1, 5, 21504]);

            for (int y = 0; y < 1024; y++) {
              for (int x = 0; x < 1024; x++) {
                final pixel = resized_image.getPixel(x, y);
                input_tensor[0][x][y][0] = pixel.r/255;
                if ((pixel.r > 0) && (pixel.r < 255)) {
                  debugPrint("R: ${pixel.r}");
                  debugPrint("input_tensor[0]: ${input_tensor[0][x][y][0]}");
                }
                input_tensor[0][x][y][1] = pixel.g;
                input_tensor[0][x][y][2] = pixel.b;
              }
            }

            // input shape (1, 1024, 1024, 3) BCHW (batch, rgb, height, width)
            // output shape(s) (1, 5, 21504) (x,y,w,h,conf)
            final model_path = 'assets/title_detection_yolov11_float32.tflite';
            final interpreter = await Interpreter.fromAsset(model_path);
            interpreter.run(input_tensor, output_tensor);

            final jpg = img.encodeJpg(resized_image);
            final new_file_path = picture.path.replaceAll(".jpg", "_brightened.jpg");
            await File(new_file_path).writeAsBytes(jpg);

            if (!context.mounted) return;

            // If the picture was taken, display it on a new screen.
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DisplayPictureScreen(
                  // Pass the automatically generated path to
                  // the DisplayPictureScreen widget.
                  imagePath: test_image,
                ),
              ),
            );
          } catch (e) {
            // If an error occurs, log the error to the console.
            print(e);
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}

// A widget that displays the picture taken by the user.
class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;

  const DisplayPictureScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      // The image is stored as a file on the device. Use the `Image.file`
      // constructor with the given path to display the image.
      body: Image.file(File(imagePath)),
    );
  }
}


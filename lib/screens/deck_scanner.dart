import 'package:camerawesome/pigeon.dart';
import 'package:flutter/material.dart';
import 'package:camerawesome/camerawesome_plugin.dart';

import 'image_processing_screen.dart';

class DeckScanner extends StatefulWidget {
  const DeckScanner({super.key});

  @override
  DeckScannerState createState() => DeckScannerState();
}

class DeckScannerState extends State<DeckScanner> {

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Scan Deck'), backgroundColor: Color.fromARGB(150, 0, 0, 0)),
        extendBodyBehindAppBar: true,
        body: CameraAwesomeBuilder.awesome(
          saveConfig: SaveConfig.photo(),
          sensorConfig: SensorConfig.single(
            sensor: Sensor.position(SensorPosition.back),
            zoom: 0.0,
          ),
          previewFit: CameraPreviewFit.contain,
          availableFilters: [],
          defaultFilter: AwesomeFilter.None,
          onMediaCaptureEvent: (mediaCapture) {
            mediaCapture.captureRequest.when(
              single: (SingleCaptureRequest singeCaptureRequest) async {
                if (mediaCapture.status == MediaCaptureStatus.capturing) {
                  String filePath = singeCaptureRequest.path!;
                  Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (context) => deckImageProcessing(filePath: filePath)
                      )
                  );
                } else if (mediaCapture.status == MediaCaptureStatus.success) {
                  debugPrint("Finished writing image file");
                }
              },
            );
          },
        )
    );
  }
}
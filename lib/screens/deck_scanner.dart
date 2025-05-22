import 'package:camerawesome/pigeon.dart';
import 'package:flutter/material.dart' hide Orientation;
import 'package:camerawesome/camerawesome_plugin.dart';

import 'image_processing_screen.dart';
import '/models/orientation.dart';

class DeckScanner extends StatefulWidget {
  const DeckScanner({super.key});

  @override
  DeckScannerState createState() => DeckScannerState();
}

class DeckScannerState extends State<DeckScanner> {

  Orientation orientationState = Orientation.auto;

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
          topActionsBuilder: (state) {
            return AwesomeTopActions(
              state: state,
              children: state is PhotoCameraState
              ? [
                AwesomeFlashButton(state: state),
                AwesomeAspectRatioButton(state: state)
              ]
              : [
                AwesomeFlashButton(state: state)
              ],
            );
          },
          bottomActionsBuilder: (state) {
            return AwesomeBottomActions(
              state: state,
              captureButton: AwesomeCaptureButton(state: state),
              left: AwesomeOrientedWidget(
                rotateWithDevice: true,
                child: TextButton(
                  onPressed: () => setState(() {
                    orientationState = Orientation.next(orientationState);
                  }),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        switch (orientationState) {
                          Orientation.auto => Icons.screen_rotation,
                          Orientation.landscape => Icons.stay_primary_landscape,
                          Orientation.portrait => Icons.stay_primary_portrait,
                        },
                        size: 35
                      ),
                      Text(
                        switch (orientationState) {
                          Orientation.auto => "Auto",
                          Orientation.landscape => "Landscape",
                          Orientation.portrait => "Portrait",
                        }
                      )
                    ],
                  ),
                )
              )
            );
          },
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
                          builder: (context) => deckImageProcessing(filePath: filePath, orientation: orientationState)
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
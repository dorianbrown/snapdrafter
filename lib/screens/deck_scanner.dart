import 'package:flutter/material.dart' hide Orientation;
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';

import '../data/models/deck.dart';
import '../data/models/deck_upsert.dart';
import '../utils/utils.dart';
import 'image_processing_screen.dart';

class DeckScanner extends StatefulWidget {
  final DeckUpsert? prefill;
  final void Function(Deck)? onDeckSaved;

  const DeckScanner({super.key, this.prefill, this.onDeckSaved});

  @override
  DeckScannerState createState() => DeckScannerState();
}

class DeckScannerState extends State<DeckScanner> with WidgetsBindingObserver {
  bool? _permissionGranted;
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPaused && _permissionGranted == false) {
        _ensureCameraPermission();
      }
      _wasPaused = false;
    }
  }

  Future<void> _ensureCameraPermission() async {
    final granted = await CamerawesomePlugin.checkAndRequestPermissions(
      false,
      checkMicrophonePermissions: false,
      checkCameraPermissions: true,
    );
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted?.hasRequiredPermissions() ?? false;
    });
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Camera access is needed to scan decks',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _ensureCameraPermission,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Deck'),
        backgroundColor: Color.fromARGB(150, 0, 0, 0),
      ),
      extendBodyBehindAppBar: true,
      body: _permissionGranted == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _permissionGranted == false
          ? _buildPermissionDenied()
          : _buildCamera(),
    );
  }

  Widget _buildCamera() {
    return CameraAwesomeBuilder.awesome(
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
                  AwesomeAspectRatioButton(state: state),
                ]
              : [AwesomeFlashButton(state: state)],
        );
      },
      bottomActionsBuilder: (state) {
        return AwesomeBottomActions(
          state: state,
          captureButton: AwesomeCaptureButton(state: state),
        );
      },
      previewFit: CameraPreviewFit.contain,
      availableFilters: [],
      defaultFilter: AwesomeFilter.None,
      onPreviewTapBuilder: (state) {
        return OnPreviewTap(
          onTap: (position, flutterPreviewSize, pixelPreviewSize) {
            state.when(
              onPhotoMode: (photoState) => photoState.focusOnPoint(
                flutterPosition: position,
                pixelPreviewSize: pixelPreviewSize,
                flutterPreviewSize: flutterPreviewSize,
                androidFocusSettings: AndroidFocusSettings(
                  autoCancelDurationInMillis: 0,
                ),
              ),
              onVideoMode: (videoState) => videoState.focusOnPoint(
                flutterPosition: position,
                pixelPreviewSize: pixelPreviewSize,
                flutterPreviewSize: flutterPreviewSize,
                androidFocusSettings: AndroidFocusSettings(
                  autoCancelDurationInMillis: 0,
                ),
              ),
              onVideoRecordingMode: (videoRecState) =>
                  videoRecState.focusOnPoint(
                    flutterPosition: position,
                    pixelPreviewSize: pixelPreviewSize,
                    flutterPreviewSize: flutterPreviewSize,
                    androidFocusSettings: AndroidFocusSettings(
                      autoCancelDurationInMillis: 0,
                    ),
                  ),
              onPreviewMode: (previewState) => previewState.focusOnPoint(
                flutterPosition: position,
                pixelPreviewSize: pixelPreviewSize,
                flutterPreviewSize: flutterPreviewSize,
                androidFocusSettings: AndroidFocusSettings(
                  autoCancelDurationInMillis: 0,
                ),
              ),
            );
          },
        );
      },
      onMediaCaptureEvent: (mediaCapture) {
        mediaCapture.captureRequest.when(
          single: (SingleCaptureRequest singeCaptureRequest) async {
            if (mediaCapture.status == MediaCaptureStatus.success) {
              String filePath = singeCaptureRequest.path!;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => deckImageProcessing(
                    filePath: filePath,
                    captureSource: CaptureSource.camera,
                    prefill: widget.prefill,
                    onDeckSaved: widget.onDeckSaved,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}

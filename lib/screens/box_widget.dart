import 'package:flutter/material.dart';
import 'recognition.dart';

class BoundingBoxWidget extends StatelessWidget {
  final List<Recognition> results;
  final double previewH; // Original image height (input to model)
  final double previewW; // Original image width (input to model)
  final double screenH;  // Screen height
  final double screenW;  // Screen width
  final double scale;    // Scaling factor applied to CameraPreview

  const BoundingBoxWidget({
    Key? key,
    required this.results,
    required this.previewH,
    required this.previewW,
    required this.screenH,
    required this.screenW,
    required this.scale,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {

    return CustomPaint(
      painter: BoxPainter(
          results: results,
          previewH: previewH,
          previewW: previewW,
          screenH: screenH,
          screenW: screenW,
          scale: scale
      ),
    );
  }
}

class BoxPainter extends CustomPainter {
  final List<Recognition> results;
  final double previewH;
  final double previewW;
  final double screenH;
  final double screenW;
  final double scale;

  BoxPainter({
    required this.results,
    required this.previewH,
    required this.previewW,
    required this.screenH,
    required this.screenW,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Coordinate transformation logic
    // This needs careful adjustment based on how CameraPreview scales the image
    // and device orientation. Assuming portrait mode and BoxFit.cover scaling.

    for (var recognition in results) {
      // Get the box location relative to the original image size
      final location = recognition.location;

      // Scale the coordinates to match the preview size on screen
      // Adjust for potential letterboxing/pillarboxing if aspect ratios don't match
      // This simple scaling assumes the preview fills the screen width or height
      // driven by the `scale` factor calculated earlier.
      final scaledRect = Rect.fromLTRB(
        location.left * scale,
        location.top * scale,
        location.right * scale,
        location.bottom * scale,
      );

      // Draw the scaled rectangle
      canvas.drawRect(scaledRect, paint);

      // Draw label and score
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(recognition.score * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white,
            backgroundColor: Colors.lightBlueAccent.withOpacity(0.7),
            fontSize: 14.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout(minWidth: 0, maxWidth: screenW); // Use screenW as max width
      final offset = Offset(scaledRect.left + 2, scaledRect.top + 2); // Position text slightly inside the box
      textPainter.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // Repaint whenever results change
    return oldDelegate is BoxPainter && oldDelegate.results != results;
  }
}
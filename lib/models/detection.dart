import 'package:image/image.dart' as img;
import 'package:snapdrafter/data/models/card.dart';

class Detection {
  Card? card;
  final String ocrText;
  final int? ocrDistance;
  final img.Image? textImage;
  final int x1;
  final int y1;
  final int x2;
  final int y2;

  Detection({
    required this.card,
    required this.ocrText,
    this.ocrDistance,
    this.textImage,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });
}
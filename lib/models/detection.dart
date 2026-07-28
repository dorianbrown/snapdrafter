import 'package:image/image.dart' as img;
import 'package:snapdrafter/data/models/card.dart';

class Detection {
  Card? card;
  final String ocrText;
  final int? ocrDistance;
  final img.Image? textImage;

  Detection({
    required this.card,
    required this.ocrText,
    this.ocrDistance,
    this.textImage
  });
}
import 'dart:ui'; // For Rect

class Recognition {
  final int id;
  final double score;
  final Rect location; // Location relative to the *original image* dimensions

  Recognition({
    required this.id,
    required this.score,
    required this.location,
  });

  @override
  String toString() {
    return 'Recognition(id: $id, score: ${score.toStringAsFixed(2)}, location: $location)';
  }
}
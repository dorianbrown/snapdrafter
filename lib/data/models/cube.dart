import 'card.dart';

class Cube {
  final String cubecobraId;
  final String name;
  final String ymd;
  final List<Card> cards;

  const Cube({
    required this.cubecobraId,
    required this.name,
    required this.ymd,
    required this.cards
  });
}
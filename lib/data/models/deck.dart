import 'package:collection/collection.dart';

import "card.dart";

class Deck {
  final int id;
  final String? name;
  final String? winLoss;
  final String? setId;
  final String? cubecobraId;
  final String ymd;
  List<Card> cards;
  List<String> tags;

  Deck({
    required this.id,
    this.name,
    this.winLoss,
    this.setId,
    this.cubecobraId,
    required this.ymd,
    required this.cards,
    this.tags = const [],
  });

  String get colors {
    String colors = cards.map(
            (card) => card.colors ?? ""
    ).toList().join("");

    String outputString = "";
    for (var symbol in ["W", "U", "B", "R", "G"]) {
      if (colors.contains(symbol)) {
        outputString += symbol;
      }
    }
    return outputString;
  }

  String generateTextExport() {
    return (cards
        .toList()..sort((a,b) => a.name.compareTo(b.name)))
        .map((card) => card.name)
        .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
        .entries.map((entry) => "${entry.value} ${entry.key}")
        .toList()
        .join("\n");
  }

  @override
  String toString() {
    return "Deck{id: $id, name: $name, win/loss: $winLoss, set: $setId, cube: $cubecobraId, ymd: $ymd}";
  }
}

import 'dart:typed_data';

import 'package:collection/collection.dart';

import "card.dart";

class Deck {
  final int id;
  final String? name;
  final String? winLoss;
  final String? setId;
  final String? cubecobraId;
  final String ymd;
  final String? imagePath;
  List<Card> cards;
  List<Card> sideboard;
  List<String> tags;

  Deck({
    required this.id,
    this.name,
    this.winLoss,
    this.setId,
    this.cubecobraId,
    required this.ymd,
    this.imagePath,
    required this.cards,
    this.sideboard = const [],
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

    String outputString = (cards
        .toList()..sort((a,b) => a.name.compareTo(b.name)))
        .map((card) => card.name)
        .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
        .entries.map((entry) => "${entry.value} ${entry.key}")
        .toList()
        .join("\n");

    if (sideboard.isNotEmpty) {
      outputString += "\nSIDEBOARD:\n";

      outputString = (sideboard
          .toList()..sort((a,b) => a.name.compareTo(b.name)))
          .map((card) => card.name)
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries.map((entry) => "${entry.value} ${entry.key}")
          .toList()
          .join("\n");
    }
    return outputString;
  }

  @override
  String toString() {
    return "Deck{id: $id, name: $name, win/loss: $winLoss, set: $setId, cube: $cubecobraId, ymd: $ymd}";
  }
}

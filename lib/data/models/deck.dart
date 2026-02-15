import 'dart:typed_data';

import 'package:collection/collection.dart';

import "card.dart";

class Deck {
  final int id;
  final String? name;
  final int? wins;
  final int? losses;
  final int? draws;
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
    this.wins,
    this.losses,
    this.draws,
    this.setId,
    this.cubecobraId,
    required this.ymd,
    this.imagePath,
    required this.cards,
    this.sideboard = const [],
    this.tags = const [],
  });

  String? get winLoss {
    if (wins == null && losses == null && draws == null) return null;
    final w = wins ?? 0;
    final l = losses ?? 0;
    final d = draws ?? 0;
    if (d == 0) return '$w-$l';
    return '$w-$l-$d';
  }

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
    if (outputString.isEmpty) {
        return "C";
    }
    return outputString;
  }

  String generateTextExport() {
    String mainboard = (cards
        .toList()..sort((a,b) => a.name.compareTo(b.name)))
        .map((card) => card.name)
        .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
        .entries.map((entry) => "${entry.value} ${entry.key}")
        .toList()
        .join("\n");
    
    if (sideboard.isNotEmpty) {
      String sideboardText = (sideboard
          .toList()..sort((a,b) => a.name.compareTo(b.name)))
          .map((card) => card.name)
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries.map((entry) => "${entry.value} ${entry.key}")
          .toList()
          .join("\n");
      return "$mainboard\nSIDEBOARD\n$sideboardText";
    }
    
    return mainboard;
  }

  @override
  String toString() {
    return "Deck{id: $id, name: $name, wins: $wins, losses: $losses, draws: $draws, set: $setId, cube: $cubecobraId, ymd: $ymd}";
  }
}

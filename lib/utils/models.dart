import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class Card {
  final String scryfallId;
  final String oracleId;
  final String name;
  final String title;
  final String type;  // First hit from list Creature, Artifact, etc
  final String? imageUri;  // URL to image
  final String? colors;  // ('R','WUBRG')
  final String? manaCost;
  final int manaValue;

  const Card({
    required this.scryfallId,
    required this.oracleId,
    required this.name,
    required this.title,
    required this.type,
    required this.imageUri,
    required this.colors,
    required this.manaCost,
    required this.manaValue
  });

  // Equality operator for comparing cards
  @override
  bool operator ==(Object other) {
    if (other is! Card) return false;
    return scryfallId == other.scryfallId;
  }

  @override
  int get hashCode => scryfallId.hashCode;

  Map<String, Object?> toMap() {
    var map = {
      "scryfall_id": scryfallId,
      "oracle_id": oracleId,
      "name": name,
      "title": title,
      "type": type,
      "image_uri": imageUri,
      "colors": colors,
      "mana_cost": manaCost,
      "mana_value": manaValue
    };
    return map;
  }

  static Card fromMap(Map<String, dynamic> map) {
    return Card(
      scryfallId: map["scryfall_id"],
      oracleId: map["oracle_id"],
      name: map["name"],
      title: map["title"],
      type: map["type"],
      imageUri: map["image_uri"],
      colors: map["colors"],
      manaCost: map["mana_cost"],
      manaValue: map["mana_value"]
    );
  }

  String color() {
    switch (colors) {
      case "W":
        return "White";
      case "U":
        return "Blue";
      case "B":
        return "Black";
      case "R":
        return "Red";
      case "G":
        return "Green";
      case "":
        return "Colorless";
      default:
        return "Multicolor";
    }
  }

  Widget createManaCost() {
    return Row(
      spacing: 1,
      children: [
        for (final match in RegExp(r'{(.*?)}|(//)').allMatches(manaCost!))
          match[0] == "//"
              ? Text(" // ", style: TextStyle(fontSize: 16))
              : SvgPicture.asset("assets/svg_icons/${match[1]!.replaceAll("/", "")}.svg", height: 14)
      ]
    );
  }

  @override
  String toString() {
    return "Card${toMap().toString()}";
  }

}

class Decklist {
  final int? id;
  final int deckId;
  final String scryfallId;

  const Decklist({
    this.id,
    required this.deckId,
    required this.scryfallId
  });

  Map<String, Object?> toMap() {
    var map = {'id': id, 'deck_id': deckId, 'scryfall_id': scryfallId};
    return map;
  }

  @override
  String toString() {
    return 'DecklistEntry{id: $id, deckId: $deckId, scryfallId: $scryfallId}';
  }
}

class Deck {
  final int id;
  final String? winLoss;
  final String? setId;
  final int? cubeId;
  final DateTime dateTime;
  List<Card> cards;

  Deck({
    required this.id,
    this.winLoss,
    this.setId,
    this.cubeId,
    required this.dateTime,
    required this.cards
  });

  String get colors {
    String colors = cards.map(
      (card) => card.colors
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
    return cards.map((card) => card.name).toList().join("\n");
  }

  @override
  String toString() {
    final ymd = dateTime.toIso8601String();
    return "Deck{id: $id, win/loss: $winLoss, set: $setId, cube: $cubeId, datetime: $ymd, cards: $cards";
  }
}

class Set {
  final String code;
  final String name;
  final String releasedAt;

  const Set({
    required this.code,
    required this.name,
    required this.releasedAt
  });

  Map<String, Object?> toMap() {
    var map = {'code': code, 'name': name, 'releasedAt': releasedAt};
    return map;
  }

  @override
  String toString() {
    return 'DecklistEntry{code: $code, name: $name, releasedAt: $releasedAt}';
  }
}

const List<String> typeOrder = [
  "Creature",
  "Planeswalker",
  "Instant",
  "Sorcery",
  "Artifact",
  "Enchantment",
  "Battle",
  "Land",
];

const List<String> colorOrder = [
  "White",
  "Blue",
  "Black",
  "Red",
  "Green",
  "Multicolor",
  "Colorless"
];

class Detection {
  final Card card;
  final String ocrText;
  final img.Image textImage;

  const Detection({
    required this.card,
    required this.ocrText,
    required this.textImage
  });
}
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';

class Card {
  final int id;
  final String name;
  final String title;
  final String type;  // First hit from list Creature, Artifact, etc
  final String? imageUri;  // URL to image
  final String? colors;  // ('R','WUBRG')
  final String? manaCost;
  final int manaValue;

  const Card({
    required this.id,
    required this.name,
    required this.title,
    required this.type,
    required this.imageUri,
    required this.colors,
    required this.manaCost,
    required this.manaValue
  });

  Map<String, Object?> toMap() {
    var map = {
      "id": id,
      "name": name,
      "title": title,
      "type": type,
      "imageUri": imageUri,
      "colors": colors,
      "manaCost": manaCost,
      "manaValue": manaValue
    };
    return map;
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
        for (final match in RegExp(r'{(.*?)}').allMatches(manaCost!))
          SvgPicture.asset(
            "assets/svg_icons/${match[1]}.svg",
            height: 14,
          )
      ]
    );
  }

  @override
  String toString() {
    return "Card{$id, $name, $title, $type, $imageUri, $colors, $manaCost, $manaValue}";
  }
}

class Decklist {
  final int? id;
  final int deckId;
  final int cardId;

  const Decklist({
    this.id,
    required this.deckId,
    required this.cardId
  });

  Map<String, Object?> toMap() {
    var map = {'id': id, 'deckId': deckId, 'cardId': cardId};
    map.removeWhere((k,v) => v == null);
    return map;
  }

  @override
  String toString() {
    return 'Dog{id: $id, deckId: $deckId, cardId: $cardId}';
  }
}

class Deck {
  final int id;
  final String name;
  final DateTime dateTime;
  final List<Card> cards;

  const Deck({
    required this.id,
    required this.name,
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
    return "Deck{id: $id, name: $name, datetime: ${dateTime.toIso8601String()}, cards: $cards";
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
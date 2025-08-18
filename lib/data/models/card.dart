import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';

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
  final String? producedMana;

  const Card({
    required this.scryfallId,
    required this.oracleId,
    required this.name,
    required this.title,
    required this.type,
    required this.imageUri,
    this.colors,
    this.manaCost,
    required this.manaValue,
    this.producedMana
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
      "mana_value": manaValue,
      "produced_mana": producedMana
    };
    return map;
  }

  bool isCreature() {
    if (type == "Creature") {
      return true;
    }
    return false;
  }

  bool isNoncreatureSpell() {
    if (type != "Creature" && type != "Land") {
      return true;
    }
    return false;
  }

  bool isNonBasicLand() {

    List<String> basics = [
      "Plains",
      "Island",
      "Swamp",
      "Mountain",
      "Forest"
    ];

    if (type == "Land" && !basics.contains(name)) {
      return true;
    }
    return false;
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
        manaValue: map["mana_value"],
        producedMana: map["produced_mana"]
    );
  }

  String color() {
    return switch (colors) {
      "W" => "White",
      "U" => "Blue",
      "B" => "Black",
      "R" => "Red",
      "G" => "Green",
      "" => "Colorless",
      _ => "Multicolor"
    };
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
class Card {
  final int id;
  final String name;
  final String title;
  final String type;  // First hit from list Creature, Artifact, etc
  final String? imageUri;  // URL to image
  final String? colors;  // ('R','WUBRG')
  final int manaValue;

  const Card({
    required this.id,
    required this.name,
    required this.title,
    required this.type,
    required this.imageUri,
    required this.colors,
    required this.manaValue
  });

  @override
  String toString() {
    return "Card{$id, $name, $title, $type, $imageUri, $colors, $manaValue}";
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
  "Battle"
  "Land",
];
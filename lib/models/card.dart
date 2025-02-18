class Card {
  final int id;
  final String scryfallId;
  final String name;
  final String flavorName;
  final String type;
  final String imageUri;
  final String color;
  final String manaValue;

  const Card({
    required this.id,
    required this.name,
    required this.scryfallId,
    required this.flavorName,
    required this.type,
    required this.imageUri,
    required this.color,
    required this.manaValue
  });
}
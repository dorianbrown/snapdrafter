class Deck {
  final int id;
  final String name;
  final DateTime dateTime;

  const Deck({
    required this.id,
    required this.name,
    required this.dateTime,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'datetime': dateTime.toIso8601String(),
    };
  }

  @override
  String toString() {
    return "Deck{id: $id, name: $name, datetime: ${dateTime.toIso8601String()}";
  }
}
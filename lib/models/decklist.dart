class Decklist {
  final int id;
  final String deckId;
  final String cardId;

  const Decklist({
    required this.id,
    required this.deckId,
    required this.cardId
  });

  Map<String, Object?> toMap() {
    return {'id': id, 'deckId': deckId, 'cardId': cardId};
  }

  @override
  String toString() {
    return 'Dog{id: $id, deckId: $deckId, cardId: $cardId}';
  }
}
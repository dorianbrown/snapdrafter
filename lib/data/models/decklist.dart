class Decklist {
  final int? id; // Assuming id is from decklists table, nullable if not always present
  final int deckId;
  final String scryfallId;

  Decklist({this.id, required this.deckId, required this.scryfallId});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deck_id': deckId,
      'scryfall_id': scryfallId,
    };
  }

  @override
  String toString() {
    return 'DecklistEntry{id: $id, deckId: $deckId, scryfallId: $scryfallId}';
  }

  // fromMap might not be needed if you always construct Decklist objects manually
}

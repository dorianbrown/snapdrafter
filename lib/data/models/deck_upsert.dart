import 'card.dart';

/// Write-model used for creating/updating a deck in the database.
///
/// - For creates: [id] should be null.
/// - For updates: [id] must be non-null.
///
/// This intentionally carries both [cards] (mainboard) and [sideboard] so
/// repository methods can manage both lists in one place.
class DeckUpsert {
  final int? id;

  final String? name;
  final String? winLoss;
  final String? setId;
  final String? cubecobraId;
  final String? ymd;

  final List<Card> cards;
  final List<Card> sideboard;

  const DeckUpsert({
    this.id,
    this.name,
    this.winLoss,
    this.setId,
    this.cubecobraId,
    this.ymd,
    required this.cards,
    this.sideboard = const [],
  });
}


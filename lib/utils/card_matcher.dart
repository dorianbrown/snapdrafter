import '/data/models/card.dart';

Card? findCardByName(String name, List<Card> allCards) {
  final lower = name.toLowerCase();

  Card? match = _first(allCards, (card) =>
      !card.name.contains(' // ') &&
      card.name.toLowerCase() == lower);

  match ??= _first(allCards, (card) =>
      card.name.contains(' // ') &&
      card.name.split(' // ').any((face) => face.toLowerCase() == lower));

  match ??= _first(allCards, (card) =>
      card.title.toLowerCase() == lower);

  return match;
}

List<Card> findCardsByNames(List<String> names, List<Card> allCards) {
  final seen = <String>{};
  final result = <Card>[];
  for (final name in names) {
    final card = findCardByName(name, allCards);
    if (card != null && seen.add(card.scryfallId)) {
      result.add(card);
    }
  }
  return result;
}

List<String> searchCardNames(String query, List<Card> allCards) {
  if (query.isEmpty) return const [];

  final lower = query.toLowerCase();
  final seen = <String>{};
  final result = <String>[];

  for (final card in allCards) {
    if (card.name.contains(' // ')) {
      for (final face in card.name.split(' // ')) {
        if (face.toLowerCase().contains(lower)) {
          if (seen.add(card.title)) {
            result.add(card.title);
          }
          break;
        }
      }
    } else {
      if (card.name.toLowerCase().contains(lower)) {
        if (seen.add(card.name)) {
          result.add(card.name);
        }
      }
    }
  }

  return result;
}

Card? _first(List<Card> cards, bool Function(Card) test) {
  for (final card in cards) {
    if (test(card)) return card;
  }
  return null;
}

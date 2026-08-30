import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/card_name_search.dart';

void main() {
  const names = [
    'Fire // Ice',
    'Firebolt',
    'Fireblast',
    'Lightning Bolt',
    'Force of Will',
    'Counterspell',
    'Island',
    'Force Spike',
  ];

  group('searchCardNames', () {
    test('returns empty for an empty or whitespace query', () {
      expect(searchCardNames(names, ''), isEmpty);
      expect(searchCardNames(names, '   '), isEmpty);
    });

    test('matches a dual-faced card by a face', () {
      expect(searchCardNames(names, 'ice'), contains('Fire // Ice'));
    });

    test('matches a dual-faced card by its full name', () {
      expect(searchCardNames(names, 'fire // ice'), contains('Fire // Ice'));
    });

    test('is case-insensitive', () {
      expect(searchCardNames(names, 'FIRE'),
          containsAll(['Fire // Ice', 'Firebolt', 'Fireblast']));
    });

    test('prioritizes prefix matches over substring matches', () {
      final result = searchCardNames(names, 'force');
      expect(result, ['Force of Will', 'Force Spike']);
    });

    test('caps the number of results', () {
      final result = searchCardNames(names, 'f', maxResults: 3);
      expect(result.length, 3);
    });

    test('returns substring matches when capped prefix matches exist', () {
      final result = searchCardNames(names, 'f', maxResults: 5);
      expect(result.take(4),
          containsAll(['Fire // Ice', 'Firebolt', 'Fireblast', 'Force of Will']));
      expect(result, contains('Force Spike'));
    });

    test('returns no matches for an unknown name', () {
      expect(searchCardNames(names, 'Black Lotus'), isEmpty);
    });
  });
}

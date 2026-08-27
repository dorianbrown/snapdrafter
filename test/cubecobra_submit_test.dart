import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/services/cubecobra_api.dart';

CubeRecordSummary _record(String id, String name, int date,
    [List<String> playerNames = const []]) {
  return CubeRecordSummary(
    id: id,
    name: name,
    date: date,
    playerNames: playerNames,
  );
}

void main() {
  group('findNewestBundleRecord', () {
    test('returns null for an empty list', () {
      expect(findNewestBundleRecord(const []), isNull);
    });

    test('returns null when no record matches the bundle name', () {
      final records = [
        _record('a', 'Draft Night', 100),
        _record('b', 'Another Draft', 200),
      ];
      expect(findNewestBundleRecord(records), isNull);
    });

    test('returns the newest matching record', () {
      final records = [
        _record('old', 'SnapDrafter Decks', 100),
        _record('new', 'SnapDrafter Decks', 300),
        _record('other', 'Draft Night', 999),
      ];
      expect(findNewestBundleRecord(records)?.id, 'new');
    });

    test('respects a custom bundle name', () {
      final records = [
        _record('a', 'SnapDrafter Decks', 100),
        _record('b', 'My bundle', 200),
      ];
      expect(findNewestBundleRecord(records, bundleName: 'My bundle')?.id, 'b');
    });

    test('skips records with empty names', () {
      final records = [
        _record('a', '', 100),
        _record('b', 'SnapDrafter Decks', 200),
      ];
      expect(findNewestBundleRecord(records)?.id, 'b');
    });
  });

  group('makeUniquePlayerName', () {
    test('returns the name when there is no collision', () {
      expect(makeUniquePlayerName('Alex', const {'Bob'}), 'Alex');
    });

    test('appends (2) on collision', () {
      expect(makeUniquePlayerName('Alex', const {'Alex'}), 'Alex (2)');
    });

    test('increments on multiple collisions', () {
      expect(
        makeUniquePlayerName('Alex', const {'Alex', 'Alex (2)', 'Alex (3)'}),
        'Alex (4)',
      );
    });

    test('handles an empty name', () {
      expect(makeUniquePlayerName('', const {}), 'Deck');
      expect(makeUniquePlayerName('', const {'Deck'}), 'Deck (2)');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/deck_text_parser.dart';

void main() {
  group('cardLineAt', () {
    test('returns the card line containing the cursor', () {
      const text = '2 Lightning Bolt\n1 Black Lotus\n4 Mox Jet';
      final info = cardLineAt(text, 7);
      expect(info, isNotNull);
      expect(info!.lineStart, 0);
      expect(info.lineEnd, 16);
      expect(info.countPrefix, '2 ');
      expect(info.nameFragment, 'Lightning Bolt');
    });

    test('works for a line in the middle of the list', () {
      const text = '2 Lightning Bolt\n1 Black Lotus\n4 Mox Jet';
      final info = cardLineAt(text, 20);
      expect(info, isNotNull);
      expect(info!.lineStart, 17);
      expect(info.lineEnd, 30);
      expect(info.countPrefix, '1 ');
      expect(info.nameFragment, 'Black Lotus');
    });

    test('works for the last line', () {
      const text = '2 Lightning Bolt\n4 Mox Jet';
      final info = cardLineAt(text, 24);
      expect(info, isNotNull);
      expect(info!.lineStart, 17);
      expect(info.lineEnd, 26);
      expect(info.countPrefix, '4 ');
      expect(info.nameFragment, 'Mox Jet');
    });

    test('works for a card line with a multi-digit count', () {
      final info = cardLineAt('12 Island', 5);
      expect(info, isNotNull);
      expect(info!.countPrefix, '12 ');
      expect(info.nameFragment, 'Island');
    });

    test('returns null on a sideboard header line', () {
      expect(cardLineAt('1 Black Lotus\nSIDEBOARD\n1 Grizzly Bears', 15),
          isNull);
    });

    test('returns null on empty lines and lines without a count', () {
      expect(cardLineAt('1 Black Lotus\n\n1 Grizzly Bears', 14), isNull);
      expect(cardLineAt('Black Lotus', 4), isNull);
    });

    test('returns an empty name fragment for a bare count with no name', () {
      final info = cardLineAt('2 Lightning Bolt\n1 ', 20);
      expect(info, isNotNull);
      expect(info!.nameFragment, isEmpty);
    });

    test('handles a cursor placed exactly on a newline as the next line', () {
      const text = '1 Black Lotus\n1 Mox Jet';
      final info = cardLineAt(text, 14);
      expect(info, isNotNull);
      expect(info!.nameFragment, 'Mox Jet');
    });

    test('clamps an out-of-range offset to the text bounds', () {
      final infoAtStart = cardLineAt('1 Mox Jet', -5);
      expect(infoAtStart, isNotNull);
      expect(infoAtStart!.nameFragment, 'Mox Jet');
      final infoAtEnd = cardLineAt('1 Mox Jet', 999);
      expect(infoAtEnd, isNotNull);
      expect(infoAtEnd!.nameFragment, 'Mox Jet');
    });
  });

  group('replaceCardNameInLine', () {
    test('replaces only the card name, preserving count and other lines', () {
      const text = '2 Lightning Bolt\n1 Black Lotus\n4 Mox Jet';
      const expected = '2 Lightning Bolt\n1 Dark Ritual\n4 Mox Jet';
      expect(replaceCardNameInLine(text, 20, 'Dark Ritual'), expected);
    });

    test('replaces on the last line and keeps the rest untouched', () {
      const text = '2 Lightning Bolt\n1 Black Lotus';
      const expected = '2 Lightning Bolt\n1 Dark Ritual';
      expect(replaceCardNameInLine(text, 24, 'Dark Ritual'), expected);
    });

    test('returns text unchanged when offset is not on a card line', () {
      const text = '1 Black Lotus\nSIDEBOARD\n1 Grizzly Bears';
      expect(replaceCardNameInLine(text, 15, 'Dark Ritual'), text);
    });

    test('handles split-card names with a // separator', () {
      const text = '2 Lightning Bolt\n1 Fire Ice';
      const expected = '2 Lightning Bolt\n1 Fire // Ice';
      expect(replaceCardNameInLine(text, 20, 'Fire // Ice'), expected);
    });
  });
}

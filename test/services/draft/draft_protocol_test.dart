import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/services/draft/draft_protocol.dart';

void main() {
  group('DraftProtocol.advertisedName', () {
    test('keeps short names unchanged', () {
      expect(DraftProtocol.advertisedName('Draft'), 'Draft');
      expect(DraftProtocol.advertisedName('123456789012'), '123456789012');
    });

    test('truncates long ASCII names to the byte budget', () {
      const name = "BallzofFury's Draft";
      final advertised = DraftProtocol.advertisedName(name);

      expect(utf8.encode(advertised).length, lessThanOrEqualTo(12));
      expect(name, startsWith(advertised));
      expect(advertised, "BallzofFury'");
    });

    test('truncates on a rune boundary for multi-byte names', () {
      // Each die emoji is 4 UTF-8 bytes; exactly three fit in the budget.
      final advertised = DraftProtocol.advertisedName('🎲🎲🎲🎲');

      expect(utf8.encode(advertised).length, 12);
      expect(advertised, '🎲🎲🎲');
    });

    test('trims surrounding whitespace', () {
      expect(DraftProtocol.advertisedName('  Draft  '), 'Draft');
    });
  });
}

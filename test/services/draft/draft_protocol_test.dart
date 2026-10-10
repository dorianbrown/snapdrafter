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

  group('DraftProtocol.draftIdFor', () {
    test('is stable for the same session id', () {
      const id = 'a1b2c3d4-0000-4000-8000-000000000000';
      expect(DraftProtocol.draftIdFor(id), DraftProtocol.draftIdFor(id));
    });

    test('differs for different session ids', () {
      expect(
        DraftProtocol.draftIdFor('session-one'),
        isNot(DraftProtocol.draftIdFor('session-two')),
      );
    });

    test('fits in an unsigned 32-bit advertisement field', () {
      for (final id in ['a', 'draft-name', 'x' * 64]) {
        final value = DraftProtocol.draftIdFor(id);
        expect(value, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });
  });

  group('advertisement round-trip', () {
    test('encodes and parses role, depth, capacity and draft id', () {
      final data = DraftProtocol.buildManufacturerData(
        role: DraftAdvertisement.roleRelay,
        depth: 2,
        capacity: 3,
        draftId: 0xDEADBEEF,
      )!;

      final parsed = DraftProtocol.parseAdvertisement([data]);
      expect(parsed, isNotNull);
      expect(parsed!.role, DraftAdvertisement.roleRelay);
      expect(parsed.depth, 2);
      expect(parsed.capacity, 3);
      expect(parsed.draftId, 0xDEADBEEF);
    });
  });
}

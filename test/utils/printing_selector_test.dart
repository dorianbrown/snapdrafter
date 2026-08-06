import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/printing_selector.dart';

Map<String, dynamic> _entry({
  String id = 'id-1',
  String? imageUri,
  required String releasedAt,
  bool promo = false,
  List<String>? frameEffects,
  bool ub = false,
  bool faces = false,
}) {
  final val = <String, dynamic>{
    'id': id,
    'released_at': releasedAt,
    'promo': promo,
    'frame_effects': frameEffects,
    'promo_types': ub ? ['universesbeyond'] : [],
    'set_type': 'expansion',
    'digital': false,
    'set_name': 'Test Set',
  };
  if (faces) {
    val['card_faces'] = [
      {'image_uris': {'normal': 'https://img/$id-face1.jpg'}},
      {'image_uris': {'normal': 'https://img/$id-face2.jpg'}},
    ];
  } else {
    val['image_uris'] = {'normal': 'https://img/$id.jpg'};
  }
  if (imageUri != null) {
    val['image_uris'] = {'normal': imageUri};
  }
  return val;
}

void main() {
  group('PrintingSelector.isUniversesBeyond', () {
    test('true when promo_types contains universesbeyond', () {
      expect(
        PrintingSelector.isUniversesBeyond({'promo_types': ['surgefoil', 'universesbeyond']}),
        true,
      );
    });

    test('false when promo_types has other values', () {
      expect(
        PrintingSelector.isUniversesBeyond({'promo_types': ['surgefoil']}),
        false,
      );
    });

    test('false when promo_types is absent', () {
      expect(PrintingSelector.isUniversesBeyond({}), false);
    });
  });

  group('PrintingSelector.extractImageUri', () {
    test('uses image_uris.normal', () {
      final uri = PrintingSelector.extractImageUri(_entry(releasedAt: '2024-01-01'));
      expect(uri, 'https://img/id-1.jpg');
    });

    test('uses first card face image for double-faced cards', () {
      final uri = PrintingSelector.extractImageUri(_entry(releasedAt: '2024-01-01', faces: true));
      expect(uri, 'https://img/id-1-face1.jpg');
    });

    test('returns null when no image exists', () {
      expect(PrintingSelector.extractImageUri({'name': 'x'}), null);
    });
  });

  group('PrintingSelector.entryRecord', () {
    test('captures the fields needed for comparison', () {
      final record = PrintingSelector.entryRecord(
        _entry(releasedAt: '2024-05-01', ub: true, frameEffects: ['showcase']),
      );
      expect(record['scryfall_id'], 'id-1');
      expect(record['image_uri'], 'https://img/id-1.jpg');
      expect(record['released_at'], '2024-05-01');
      expect(record['promo'], false);
      expect(record['frame_effects'], ['showcase']);
      expect(record['is_ub'], true);
    });
  });

  group('PrintingSelector.oracleFields', () {
    test('extracts fields from a normal card', () {
      final fields = PrintingSelector.oracleFields({
        'name': 'Grizzly Bears',
        'type_line': 'Creature — Bear',
        'colors': ['G'],
        'mana_cost': '{1}{G}',
        'cmc': 2.0,
        'oracle_text': 'Trample',
      });
      expect(fields['name'], 'Grizzly Bears');
      expect(fields['title'], 'Grizzly Bears');
      expect(fields['type'], 'Creature');
      expect(fields['colors'], 'G');
      expect(fields['mana_cost'], '{1}{G}');
      expect(fields['mana_value'], 2);
      expect(fields['oracle_text'], 'Trample');
    });

    test('prepare-style faces: falls back to card-level colors when the '
        'first face has no colors field', () {
      final fields = PrintingSelector.oracleFields({
        'name': 'Swords to Plowshares',
        'type_line': 'Instant',
        'colors': ['W'],
        'cmc': 1.0,
        'card_faces': [
          {'name': 'Emeritus of Truce', 'mana_cost': '{1}{W}{W}'},
          {'name': 'Swords to Plowshares', 'mana_cost': '{W}'},
        ],
      });
      expect(fields['colors'], 'W');
      expect(fields['mana_cost'], '{1}{W}{W}');
      expect(fields['mana_value'], 1);
    });

    test('transform-style faces: face colors and mana cost win', () {
      final fields = PrintingSelector.oracleFields({
        'name': 'Voldaren Bloodcaster // Bloodbat Summoner',
        'type_line': 'Creature — Vampire Warlock',
        'cmc': 3.0,
        'card_faces': [
          {
            'name': 'Voldaren Bloodcaster',
            'colors': ['B', 'R'],
            'mana_cost': '{1}{B}{R}',
            'oracle_text': 'Flying',
          },
          {
            'name': 'Bloodbat Summoner',
            'colors': ['B', 'R'],
            'mana_cost': '{1}{B}{R}',
            'oracle_text': 'At the beginning of combat...',
          },
        ],
      });
      expect(fields['title'], 'Voldaren Bloodcaster');
      expect(fields['colors'], 'BR');
      expect(fields['mana_cost'], '{1}{B}{R}');
      expect(fields['oracle_text'], 'Flying\nAt the beginning of combat...');
    });

    test('joins oracle text of faces with newline, skipping empty faces', () {
      final fields = PrintingSelector.oracleFields({
        'name': 'Two Faces',
        'type_line': 'Creature — Human',
        'cmc': 2.0,
        'card_faces': [
          {'name': 'One', 'colors': ['W'], 'oracle_text': ''},
          {'name': 'Two', 'colors': ['W'], 'oracle_text': 'Vigilance'},
        ],
      });
      expect(fields['oracle_text'], 'Vigilance');
    });
  });

  group('PrintingSelector.compareRawToRecord', () {
    test('matches compareEntries on entryRecord for equal semantics', () {
      final val = _entry(
          releasedAt: '2024-06-01', ub: true, promo: true, frameEffects: ['showcase']);
      final record = PrintingSelector.entryRecord(
          _entry(releasedAt: '2024-03-01'));
      expect(
        PrintingSelector.compareRawToRecord(val, record),
        PrintingSelector.compareEntries(
            PrintingSelector.entryRecord(val), record),
      );
    });

    test('newer raw entry beats stored record', () {
      final val = _entry(releasedAt: '2025-01-01');
      final record = PrintingSelector.entryRecord(_entry(releasedAt: '2023-01-01'));
      expect(PrintingSelector.compareRawToRecord(val, record), lessThan(0));
    });

    test('older raw entry loses to stored record', () {
      final val = _entry(releasedAt: '2022-01-01');
      final record = PrintingSelector.entryRecord(_entry(releasedAt: '2023-01-01'));
      expect(PrintingSelector.compareRawToRecord(val, record), greaterThan(0));
    });

    test('raw entry with more frame effects loses on ties', () {
      final val = _entry(releasedAt: '2024-01-01', frameEffects: ['showcase']);
      final record = PrintingSelector.entryRecord(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareRawToRecord(val, record), greaterThan(0));
    });
  });

  group('PrintingSelector.compareEntries', () {
    Map<String, dynamic> record(Map<String, dynamic> entry) =>
        PrintingSelector.entryRecord(entry);

    test('newest release wins', () {
      final older = record(_entry(releasedAt: '2023-01-01'));
      final newer = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(newer, older), lessThan(0));
      expect(PrintingSelector.compareEntries(older, newer), greaterThan(0));
    });

    test('non-promo wins on equal release date', () {
      final promo = record(_entry(releasedAt: '2024-01-01', promo: true));
      final regular = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(regular, promo), lessThan(0));
    });

    test('no special frame effects wins on equal date and promo status', () {
      final showcase = record(
          _entry(releasedAt: '2024-01-01', frameEffects: ['showcase']));
      final regular = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(regular, showcase), lessThan(0));
    });

    test('non-UB wins on equal date, promo and frame status', () {
      final ub = record(_entry(releasedAt: '2024-01-01', ub: true));
      final nonUb = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(nonUb, ub), lessThan(0));
    });

    test('returns zero for identical entries', () {
      final a = record(_entry(releasedAt: '2024-01-01'));
      final b = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(a, b), 0);
    });

    test('UB entry preferred over older non-UB entry', () {
      final ubNewer = record(_entry(releasedAt: '2025-01-01', ub: true));
      final nonUbOlder = record(_entry(releasedAt: '2023-01-01'));
      expect(PrintingSelector.compareEntries(ubNewer, nonUbOlder), lessThan(0));
    });
  });
}

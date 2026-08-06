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
  String setType = 'expansion',
  bool fullArt = false,
  bool textless = false,
  bool boosterFun = false,
  bool promoPack = false,
  String lang = 'en',
}) {
  final promoTypes = <String>[
    if (ub) 'universesbeyond',
    if (boosterFun) 'boosterfun',
    if (promoPack) 'promopack'
  ];
  final val = <String, dynamic>{
    'id': id,
    'released_at': releasedAt,
    'promo': promo,
    'frame_effects': frameEffects,
    'promo_types': promoTypes,
    'set_type': setType,
    'full_art': fullArt,
    'textless': textless,
    'lang': lang,
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

  group('PrintingSelector.isExcludedFromFirstPrinting', () {
    test('true for all basic lands', () {
      for (final name in ['Plains', 'Island', 'Swamp', 'Mountain', 'Forest']) {
        expect(
          PrintingSelector.isExcludedFromFirstPrinting({'name': name}),
          true,
          reason: '$name should be excluded',
        );
      }
    });

    test('false for other cards', () {
      expect(PrintingSelector.isExcludedFromFirstPrinting({'name': 'Grizzly Bears'}), false);
      expect(PrintingSelector.isExcludedFromFirstPrinting({'name': 'Arcane Signet'}), false);
      expect(PrintingSelector.isExcludedFromFirstPrinting({'name': 'Fire // Ice'}), false);
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
      expect(record['special'], true);
      expect(record['is_ub'], true);
    });

    test('marks regular printings as non-special', () {
      final record = PrintingSelector.entryRecord(_entry(releasedAt: '2024-05-01'));
      expect(record['special'], false);
    });

    test('captures the language', () {
      final english = PrintingSelector.entryRecord(_entry(releasedAt: '2024-05-01'));
      expect(english['english'], true);
      final japanese = PrintingSelector.entryRecord(
          _entry(releasedAt: '2024-05-01', lang: 'ja'));
      expect(japanese['english'], false);
    });
  });

  group('PrintingSelector.isSpecialPrinting', () {
    test('false for a regular printing', () {
      expect(PrintingSelector.isSpecialPrinting(_entry(releasedAt: '2024-01-01')), false);
    });

    test('true for promo printings', () {
      expect(
        PrintingSelector.isSpecialPrinting(_entry(releasedAt: '2024-01-01', promo: true)),
        true,
      );
    });

    test('true for alternate frame effects', () {
      for (final fx in [
        'borderless',
        'showcase',
        'extendedart',
        'fullart',
        'inverted',
        'etched',
        'shatteredglass',
        'colorshifted',
        'miracle',
      ]) {
        expect(
          PrintingSelector.isSpecialPrinting(
              _entry(releasedAt: '2024-01-01', frameEffects: [fx])),
          true,
          reason: 'frame effect $fx should be special',
        );
      }
    });

    test('false for regular frame effects', () {
      for (final fx in ['legendary', 'enchantment', 'snow', 'sunmoondfc']) {
        expect(
          PrintingSelector.isSpecialPrinting(
              _entry(releasedAt: '2024-01-01', frameEffects: [fx])),
          false,
          reason: 'frame effect $fx should not be special',
        );
      }
    });

    test('true for Secret Lair and special product set types', () {
      for (final setType in ['box', 'promo', 'memorabilia', 'masterpiece']) {
        expect(
          PrintingSelector.isSpecialPrinting(
              _entry(releasedAt: '2024-01-01', setType: setType)),
          true,
          reason: 'set_type $setType should be special',
        );
      }
    });

    test('false for regular product set types', () {
      for (final setType in ['expansion', 'core', 'masters', 'commander']) {
        expect(
          PrintingSelector.isSpecialPrinting(
              _entry(releasedAt: '2024-01-01', setType: setType)),
          false,
        );
      }
    });

    test('true for booster fun variants', () {
      expect(
        PrintingSelector.isSpecialPrinting(
            _entry(releasedAt: '2024-01-01', boosterFun: true)),
        true,
      );
    });

    test('true for promo pack variants', () {
      expect(
        PrintingSelector.isSpecialPrinting(
            _entry(releasedAt: '2024-01-01', promoPack: true)),
        true,
      );
    });

    test('true for full-art and textless printings', () {
      expect(
        PrintingSelector.isSpecialPrinting(
            _entry(releasedAt: '2024-01-01', fullArt: true)),
        true,
      );
      expect(
        PrintingSelector.isSpecialPrinting(
            _entry(releasedAt: '2024-01-01', textless: true)),
        true,
      );
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

    test('language preference matches compareEntries semantics', () {
      final english = _entry(releasedAt: '2018-04-27');
      final foreign =
          PrintingSelector.entryRecord(_entry(releasedAt: '2026-08-14', lang: 'dw'));
      expect(PrintingSelector.compareRawToRecord(english, foreign), lessThan(0));
      expect(
        PrintingSelector.compareRawToRecord(english, foreign),
        PrintingSelector.compareEntries(
            PrintingSelector.entryRecord(english), foreign),
      );
    });

    test('non-UB raw entry beats newer UB stored record', () {
      final nonUb = _entry(releasedAt: '2023-01-01');
      final ubRecord =
          PrintingSelector.entryRecord(_entry(releasedAt: '2025-01-01', ub: true));
      expect(PrintingSelector.compareRawToRecord(nonUb, ubRecord), lessThan(0));
      expect(
        PrintingSelector.compareRawToRecord(nonUb, ubRecord),
        PrintingSelector.compareEntries(
            PrintingSelector.entryRecord(nonUb), ubRecord),
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

  group('PrintingSelector.compareFirstPrintingEntries', () {
    Map<String, dynamic> record(Map<String, dynamic> entry) =>
        PrintingSelector.entryRecord(entry);

    test('earliest release wins', () {
      final older = record(_entry(releasedAt: '1993-08-05'));
      final newer = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareFirstPrintingEntries(older, newer), lessThan(0));
      expect(PrintingSelector.compareFirstPrintingEntries(newer, older), greaterThan(0));
    });

    test('earliest special printing wins over newer regular printing', () {
      final originalSpecial =
          record(_entry(releasedAt: '1995-04-01', setType: 'promo'));
      final newerRegular = record(_entry(releasedAt: '2024-01-01'));
      expect(
          PrintingSelector.compareFirstPrintingEntries(originalSpecial, newerRegular),
          lessThan(0));
    });

    test('regular wins over special on equal release date', () {
      final showcase =
          record(_entry(releasedAt: '2024-01-01', frameEffects: ['showcase']));
      final regular = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareFirstPrintingEntries(regular, showcase), lessThan(0));
    });

    test('English wins over foreign on equal release date', () {
      final japanese = record(_entry(releasedAt: '2019-05-03', lang: 'ja'));
      final english = record(_entry(releasedAt: '2019-05-03'));
      expect(PrintingSelector.compareFirstPrintingEntries(english, japanese), lessThan(0));
    });

    test('non-UB wins over UB on equal release date and tie-breaks', () {
      final ub = record(_entry(releasedAt: '2022-10-07', ub: true));
      final nonUb = record(_entry(releasedAt: '2022-10-07'));
      expect(PrintingSelector.compareFirstPrintingEntries(nonUb, ub), lessThan(0));
    });

    test('returns zero for identical entries', () {
      final a = record(_entry(releasedAt: '2024-01-01'));
      final b = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareFirstPrintingEntries(a, b), 0);
    });
  });

  group('PrintingSelector.compareFirstPrintingRawToRecord', () {
    test('matches compareFirstPrintingEntries on entryRecord for equal semantics', () {
      final val = _entry(
          releasedAt: '1993-08-05', ub: false, promo: false, lang: 'en');
      final record = PrintingSelector.entryRecord(
          _entry(releasedAt: '2024-06-01', ub: true, promo: true, lang: 'ja'));
      expect(
        PrintingSelector.compareFirstPrintingRawToRecord(val, record),
        PrintingSelector.compareFirstPrintingEntries(
            PrintingSelector.entryRecord(val), record),
      );
    });

    test('earlier raw entry beats stored record', () {
      final val = _entry(releasedAt: '1993-08-05');
      final record =
          PrintingSelector.entryRecord(_entry(releasedAt: '2024-01-01'));
      expect(
          PrintingSelector.compareFirstPrintingRawToRecord(val, record), lessThan(0));
    });

    test('later raw entry loses to stored record', () {
      final val = _entry(releasedAt: '2024-01-01');
      final record =
          PrintingSelector.entryRecord(_entry(releasedAt: '1993-08-05'));
      expect(
          PrintingSelector.compareFirstPrintingRawToRecord(val, record), greaterThan(0));
    });

    test('equal date: English raw entry beats foreign stored record', () {
      final english = _entry(releasedAt: '2019-05-03');
      final japanese = PrintingSelector.entryRecord(
          _entry(releasedAt: '2019-05-03', lang: 'ja'));
      expect(
          PrintingSelector.compareFirstPrintingRawToRecord(english, japanese),
          lessThan(0));
    });
  });

  group('PrintingSelector.compareEntries', () {
    Map<String, dynamic> record(Map<String, dynamic> entry) =>
        PrintingSelector.entryRecord(entry);

    test('regular printing wins over newer special printing', () {
      final regular = record(_entry(releasedAt: '2023-01-01'));
      final specialNewer =
          record(_entry(releasedAt: '2026-01-01', frameEffects: ['inverted']));
      expect(PrintingSelector.compareEntries(regular, specialNewer), lessThan(0));
    });

    test('newest release wins among regular printings', () {
      final older = record(_entry(releasedAt: '2023-01-01'));
      final newer = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(newer, older), lessThan(0));
      expect(PrintingSelector.compareEntries(older, newer), greaterThan(0));
    });

    test('English wins over foreign printing on equal release date', () {
      final japanese = record(_entry(releasedAt: '2024-01-01', lang: 'ja'));
      final english = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(english, japanese), lessThan(0));
    });

    test('older English printing wins over newer foreign printing', () {
      final olderEnglish = record(_entry(releasedAt: '2018-04-27'));
      final newerForeign =
          record(_entry(releasedAt: '2026-08-14', lang: 'dw'));
      expect(PrintingSelector.compareEntries(olderEnglish, newerForeign), lessThan(0));
    });

    test('newest foreign printing wins when no English exists', () {
      final olderForeign = record(_entry(releasedAt: '2023-01-01', lang: 'ja'));
      final newerForeign = record(_entry(releasedAt: '2026-01-01', lang: 'ja'));
      expect(PrintingSelector.compareEntries(newerForeign, olderForeign), lessThan(0));
    });

    test('newest English printing wins among English printings', () {
      final older = record(_entry(releasedAt: '2023-01-01'));
      final newer = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(newer, older), lessThan(0));
    });

    test('newest special printing wins when no regular exists', () {
      final olderSpecial =
          record(_entry(releasedAt: '2023-01-01', setType: 'box'));
      final newerSpecial =
          record(_entry(releasedAt: '2026-01-01', setType: 'box'));
      expect(PrintingSelector.compareEntries(newerSpecial, olderSpecial), lessThan(0));
    });

    test('non-UB wins on equal date and special status', () {
      final ub = record(_entry(releasedAt: '2024-01-01', ub: true));
      final nonUb = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(nonUb, ub), lessThan(0));
    });

    test('returns zero for identical entries', () {
      final a = record(_entry(releasedAt: '2024-01-01'));
      final b = record(_entry(releasedAt: '2024-01-01'));
      expect(PrintingSelector.compareEntries(a, b), 0);
    });

    test('non-UB printing preferred over newer UB printing', () {
      final ubNewer = record(_entry(releasedAt: '2025-01-01', ub: true));
      final nonUbOlder = record(_entry(releasedAt: '2023-01-01'));
      expect(PrintingSelector.compareEntries(nonUbOlder, ubNewer), lessThan(0));
    });

    test('newest UB printing wins when no non-UB exists', () {
      final ubOlder = record(_entry(releasedAt: '2023-01-01', ub: true));
      final ubNewer = record(_entry(releasedAt: '2025-01-01', ub: true));
      expect(PrintingSelector.compareEntries(ubNewer, ubOlder), lessThan(0));
    });
  });
}

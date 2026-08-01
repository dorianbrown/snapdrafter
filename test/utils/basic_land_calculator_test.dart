import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/basic_land_calculator.dart';
import 'package:snapdrafter/data/models/card.dart';
import 'package:snapdrafter/data/models/deck.dart';

Card _card({
  required String scryfallId,
  required String name,
  String type = 'Creature',
  String? manaCost,
  int manaValue = 2,
  String? producedMana,
  String? colors,
}) {
  return Card(
    scryfallId: scryfallId,
    oracleId: scryfallId,
    name: name,
    title: name.split(' // ')[0],
    type: type,
    imageUri: null,
    manaCost: manaCost,
    manaValue: manaValue,
    producedMana: producedMana,
    colors: colors,
  );
}

Deck _deck(List<Card> cards) {
  return Deck(
    id: 0,
    ymd: '2025-01-01',
    cards: cards,
  );
}

void main() {
  group('detectFixingTag', () {
    test('land tutor — Rampant Growth', () {
      expect(
        detectFixingTag('Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.'),
        FixingTag.landTutor,
      );
    });

    test('land tutor — Evolving Wilds', () {
      expect(
        detectFixingTag('{T}, Sacrifice Evolving Wilds: Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.'),
        FixingTag.landTutor,
      );
    });

    test('land tutor — Cultivate', () {
      expect(
        detectFixingTag('Search your library for up to two basic land cards, reveal those cards, put one onto the battlefield tapped and the other into your hand, then shuffle.'),
        FixingTag.landTutor,
      );
    });

    test('land tutor — Arid Mesa (specific types)', () {
      expect(
        detectFixingTag('{T}, Pay 1 life, Sacrifice Arid Mesa: Search your library for a Mountain or Plains card, put it onto the battlefield, then shuffle.'),
        FixingTag.landTutor,
      );
    });

    test('repeatable mana — Llanowar Elves', () {
      expect(
        detectFixingTag('{T}: Add {G}.'),
        FixingTag.repeatableMana,
      );
    });

    test('repeatable mana — Arcane Signet', () {
      expect(
        detectFixingTag('{T}: Add one mana of any color in your commander\'s color identity.'),
        FixingTag.repeatableMana,
      );
    });

    test('treasure — Deadly Dispute', () {
      expect(
        detectFixingTag('As an additional cost to cast this spell, sacrifice an artifact or creature. Draw two cards and create a Treasure token.'),
        FixingTag.treasure,
      );
    });

    test('treasure — Magda, Brazen Outlaw', () {
      expect(
        detectFixingTag('At the beginning of combat on your turn, create a tapped Treasure token.'),
        FixingTag.treasure,
      );
    });

    test('one-shot mana — Dark Ritual', () {
      expect(
        detectFixingTag('Add {B}{B}{B}.'),
        FixingTag.oneShotMana,
      );
    });

    test('one-shot mana — Manamorphose (pattern misses no-curly-brace format)', () {
      expect(
        detectFixingTag('Add two mana in any combination of colors. Draw a card.'),
        FixingTag.none,
      );
    }, tags: 'known-edge-case');

    test('none — Lightning Bolt', () {
      expect(
        detectFixingTag('Lightning Bolt deals 3 damage to any target.'),
        FixingTag.none,
      );
    });

    test('none — generic creature', () {
      expect(
        detectFixingTag('Flying, vigilance'),
        FixingTag.none,
      );
    });

    test('treasure takes priority over add pattern', () {
      expect(
        detectFixingTag('Create a Treasure token. (It\'s an artifact with "{T}, Sacrifice this artifact: Add one mana of any color.")'),
        FixingTag.treasure,
      );
    });
  });

  group('getFixingWeight', () {
    test('landTutor = 1.0', () {
      expect(getFixingWeight(FixingTag.landTutor), 1.0);
    });

    test('repeatableMana = 0.75', () {
      expect(getFixingWeight(FixingTag.repeatableMana), 0.75);
    });

    test('treasure = 0.50', () {
      expect(getFixingWeight(FixingTag.treasure), 0.50);
    });

    test('oneShotMana = 0.50', () {
      expect(getFixingWeight(FixingTag.oneShotMana), 0.50);
    });

    test('none = 0.0', () {
      expect(getFixingWeight(FixingTag.none), 0.0);
    });
  });

  group('requiredFloor', () {
    test('1-drop 1 pip → 9', () {
      expect(requiredFloor(1, 1), 9);
    });

    test('2-drop 2 pips → 11', () {
      expect(requiredFloor(2, 2), 11);
    });

    test('2-drop 1 pip → 8', () {
      expect(requiredFloor(2, 1), 8);
    });

    test('3-drop 1 pip → 7', () {
      expect(requiredFloor(3, 1), 7);
    });

    test('3-drop 2+ pips → 10', () {
      expect(requiredFloor(3, 2), 10);
      expect(requiredFloor(3, 3), 10);
    });

    test('4-drop 1 pip → 6', () {
      expect(requiredFloor(4, 1), 6);
    });

    test('4-drop 2+ pips → 10', () {
      expect(requiredFloor(4, 2), 10);
      expect(requiredFloor(5, 3), 10);
    });

    test('0 pips → 0', () {
      expect(requiredFloor(2, 0), 0);
    });
  });

  group('calculateBasicLandsWithOracleTexts', () {
    test('17 lands, no ramp, balanced UW deck', () {
      final cards = [
        _card(scryfallId: 'a', name: 'White One Drop', manaCost: '{W}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Blue One Drop', manaCost: '{U}', manaValue: 1),
        _card(scryfallId: 'c', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'd', name: 'Island', type: 'Land'),
      ];

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.nonBasicLandCount, 0);
      expect(result.rampCount, 0);
      expect(result.totalLands, 17);
      expect(result.basicLandSlots, 17);
      expect(result.basics['White'], isNotNull);
      expect(result.basics['Blue'], isNotNull);
      expect(result.basics['White']! + result.basics['Blue']!, 17);
    });

    test('ramp reduces total land count', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Llanowar Elves', manaCost: '{G}', manaValue: 1, producedMana: 'G'),
        _card(scryfallId: 'b', name: 'Birds of Paradise', manaCost: '{G}', manaValue: 1, producedMana: 'WUBRG'),
        _card(scryfallId: 'c', name: 'Grizzly Bears', manaCost: '{1}{G}', manaValue: 2),
        _card(scryfallId: 'd', name: 'Forest', type: 'Land'),
      ];

      final oracleTexts = {
        'a': ['{T}: Add {G}.'],
        'b': ['{T}: Add one mana of any color.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.rampCount, 2);
      expect(result.totalLands, 16);
    });

    test('ramp MV > 2 does not reduce land count', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Cultivate', manaCost: '{2}{G}', manaValue: 3, producedMana: 'G'),
        _card(scryfallId: 'b', name: 'Grizzly Bears', manaCost: '{1}{G}', manaValue: 2),
        _card(scryfallId: 'c', name: 'Forest', type: 'Land'),
      ];

      final oracleTexts = {
        'a': ['Search your library for up to two basic land cards, reveal those cards, put one onto the battlefield tapped and the other into your hand, then shuffle.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.rampCount, 0);
      expect(result.totalLands, 17);
    });

    test('non-basic duals reduce basic land slots', () {
      final cards = [
        _card(scryfallId: 'a', name: 'White One Drop', manaCost: '{W}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Blue One Drop', manaCost: '{U}', manaValue: 1),
        _card(scryfallId: 'c', name: 'Tundra', type: 'Land', producedMana: 'WU'),
      ];

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.nonBasicLandCount, 1);
      expect(result.basicLandSlots, 16);
    });

    test('heavier pip requirements get proportionally more basics', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Red Card', manaCost: '{R}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Heavy White', manaCost: '{W}{W}{W}', manaValue: 3),
        _card(scryfallId: 'c', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'd', name: 'Mountain', type: 'Land'),
      ];

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.basics['White']! > result.basics['Red']!, true,
          reason: 'Triple W should get more basics than single R');
    });

    test('mono-color deck gets all basics in that color', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Red Card', manaCost: '{R}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Red Card 2', manaCost: '{1}{R}', manaValue: 2),
        _card(scryfallId: 'c', name: 'Mountain', type: 'Land'),
      ];

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.basics['Red'], 17);
      expect(result.basics.containsKey('White'), false);
    });

    test('virtual fixing reduces basics for that color', () {
      final cards = [
        _card(scryfallId: 'a', name: 'White One Drop', manaCost: '{W}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Blue One Drop', manaCost: '{U}', manaValue: 1),
        _card(scryfallId: 'c', name: 'Arcane Signet', manaCost: '{2}', manaValue: 2, producedMana: 'WUBRG'),
        _card(scryfallId: 'd', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'e', name: 'Island', type: 'Land'),
      ];

      final oracleTexts = {
        'c': ['{T}: Add one mana of any color in your commander\'s color identity.'],
      };

      final signetResult = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(signetResult.virtualFixing['White']!, 0.75);
      expect(signetResult.virtualFixing['Blue']!, 0.75);
    });

    test('treasure fixes all deck colors at 0.50 weight', () {
      final cards = [
        _card(scryfallId: 'a', name: 'White One Drop', manaCost: '{W}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Blue One Drop', manaCost: '{U}', manaValue: 1),
        _card(scryfallId: 'c', name: 'Deadly Dispute', manaCost: '{1}{B}', manaValue: 2),
        _card(scryfallId: 'd', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'e', name: 'Island', type: 'Land'),
      ];

      final oracleTexts = {
        'c': ['As an additional cost to cast this spell, sacrifice an artifact or creature. Draw two cards and create a Treasure token.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.virtualFixing['White']!, 0.50);
      expect(result.virtualFixing['Blue']!, 0.50);
      expect(result.rampCount, 1);
    });

    test('fetch land (no producedMana) counts as source for all deck colors', () {
      final cards = [
        _card(scryfallId: 'a', name: 'White One Drop', manaCost: '{W}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Blue One Drop', manaCost: '{U}', manaValue: 1),
        _card(scryfallId: 'c', name: 'Evolving Wilds', type: 'Land'),
        _card(scryfallId: 'd', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'e', name: 'Island', type: 'Land'),
      ];

      final oracleTexts = {
        'c': ['{T}, Sacrifice Evolving Wilds: Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.nonBasicLandCount, 1);
      expect(result.basicLandSlots, 16);
    });

    test('floor check shifts basics if 1-drop requirement not met', () {
      final cards = List.generate(12, (i) =>
        _card(scryfallId: 'a$i', name: 'White One Drop $i', manaCost: '{W}', manaValue: 2),
      );
      cards.add(_card(scryfallId: 'b0', name: 'Blue Card', manaCost: '{6}{U}{U}', manaValue: 8));
      cards.add(_card(scryfallId: 'b1', name: 'Blue Card 2', manaCost: '{5}{U}', manaValue: 6));
      cards.add(_card(scryfallId: 'c', name: 'Plains', type: 'Land'));
      cards.add(_card(scryfallId: 'd', name: 'Island', type: 'Land'));

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.basics['White']!, greaterThanOrEqualTo(7));
    });

    test('land tutor (Rampant Growth) counts as ramp and fixing', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Rampant Growth', manaCost: '{1}{G}', manaValue: 2),
        _card(scryfallId: 'a2', name: 'Rampant Growth 2', manaCost: '{1}{G}', manaValue: 2),
        _card(scryfallId: 'b', name: 'Grizzly Bears', manaCost: '{1}{G}', manaValue: 2),
        _card(scryfallId: 'c', name: 'Forest', type: 'Land'),
      ];

      final oracleTexts = {
        'a': ['Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.'],
        'a2': ['Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.rampCount, 2);
      expect(result.virtualFixing['Green']!, 2.0);
      expect(result.totalLands, 16);
    });

    test('empty deck returns zero basics', () {
      final result = calculateBasicLandsWithOracleTexts(_deck([]), {});

      expect(result.totalLands, 17);
      expect(result.basicLandSlots, 17);
      expect(result.basics, isEmpty);
    });

    test('all land deck', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'b', name: 'Island', type: 'Land'),
        _card(scryfallId: 'c', name: 'Swamp', type: 'Land'),
        _card(scryfallId: 'd', name: 'Mountain', type: 'Land'),
        _card(scryfallId: 'e', name: 'Forest', type: 'Land'),
      ];

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.totalLands, 17);
      expect(result.basicLandSlots, 17);
      expect(result.nonBasicLandCount, 0);
      expect(result.basics, isEmpty);
    });

    test('many non-basic lands can reduce basics to zero', () {
      final cards = List.generate(20, (i) =>
        _card(scryfallId: 'nb$i', name: 'Hallowed Fountain', type: 'Land', producedMana: 'WU'),
      );
      cards.add(_card(scryfallId: 'a', name: 'White Card', manaCost: '{W}', manaValue: 1));
      cards.add(_card(scryfallId: 'b', name: 'Blue Card', manaCost: '{U}', manaValue: 1));

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.nonBasicLandCount, 20);
      expect(result.basicLandSlots, 0);
    });

    test('treasure with mana value <= 2 counts for ramp and virtual fixing', () {
      final cards = [
        _card(scryfallId: 'a', name: 'White Card', manaCost: '{W}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Magda', manaCost: '{1}{R}', manaValue: 2),
        _card(scryfallId: 'c', name: 'Plains', type: 'Land'),
        _card(scryfallId: 'd', name: 'Mountain', type: 'Land'),
      ];

      final oracleTexts = {
        'b': ['At the beginning of combat on your turn, create a tapped Treasure token.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.rampCount, 1);
      expect(result.virtualFixing['White']!, 0.50);
      expect(result.virtualFixing['Red']!, 0.50);
    });

    test('Dark Ritual does NOT count as ramp (one-shot mana, not repeatable)', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Dark Ritual', manaCost: '{B}', manaValue: 1, producedMana: 'B'),
        _card(scryfallId: 'b', name: 'Swamp', type: 'Land'),
      ];

      final oracleTexts = {
        'a': ['Add {B}{B}{B}.'],
      };

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), oracleTexts);

      expect(result.rampCount, 0);
      expect(result.virtualFixing['Black']!, 0.50);
    });

    test('3-color deck distributes basics across all colors', () {
      final cards = [
        _card(scryfallId: 'a', name: 'Red Card', manaCost: '{R}', manaValue: 1),
        _card(scryfallId: 'b', name: 'Blue Card', manaCost: '{U}', manaValue: 1),
        _card(scryfallId: 'c', name: 'Green Card', manaCost: '{G}', manaValue: 1),
        _card(scryfallId: 'd', name: 'Mountain', type: 'Land'),
        _card(scryfallId: 'e', name: 'Island', type: 'Land'),
        _card(scryfallId: 'f', name: 'Forest', type: 'Land'),
      ];

      final result = calculateBasicLandsWithOracleTexts(_deck(cards), {});

      expect(result.basics.keys, containsAll(['Red', 'Blue', 'Green']));
      expect(result.basics['Red']! + result.basics['Blue']! + result.basics['Green']!, 17);
    });
  });
}

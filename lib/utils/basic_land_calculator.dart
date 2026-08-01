import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

import '../data/models/deck.dart';
import '../data/models/card.dart';
import 'scryfall_api.dart';

const _colorCharToName = <String, String>{
  'W': 'White',
  'U': 'Blue',
  'B': 'Black',
  'R': 'Red',
  'G': 'Green',
};

const _basicLandNames = {
  'Plains',
  'Island',
  'Swamp',
  'Mountain',
  'Forest',
};

enum FixingTag {
  landTutor,
  repeatableMana,
  treasure,
  oneShotMana,
  none,
}

class BasicLandResult {
  final Map<String, int> basics;
  final int totalLands;
  final int basicLandSlots;
  final int nonBasicLandCount;
  final int rampCount;
  final Map<String, double> weightedPips;
  final Map<String, double> virtualFixing;

  const BasicLandResult({
    required this.basics,
    required this.totalLands,
    required this.basicLandSlots,
    required this.nonBasicLandCount,
    required this.rampCount,
    required this.weightedPips,
    required this.virtualFixing,
  });
}

final Map<String, List<String>> _oracleTextCache = {};

Future<List<String>> _fetchOracleTexts(String scryfallId) async {
  if (_oracleTextCache.containsKey(scryfallId)) {
    return _oracleTextCache[scryfallId]!;
  }

  try {
    final response = await scryfallGet('/cards/$scryfallId');
    if (response.statusCode != 200) {
      _oracleTextCache[scryfallId] = [];
      return [];
    }

    final data = json.decode(response.body);
    final List<String> texts = [];

    if (data['card_faces'] != null) {
      for (final face in data['card_faces']) {
        if (face['oracle_text'] != null) {
          texts.add(face['oracle_text'] as String);
        }
      }
    } else if (data['oracle_text'] != null) {
      texts.add(data['oracle_text'] as String);
    }

    _oracleTextCache[scryfallId] = texts;
    return texts;
  } catch (_) {
    _oracleTextCache[scryfallId] = [];
    return [];
  }
}

Future<Map<String, List<String>>> _fetchAllOracleTexts(
  List<Card> cards,
) async {
  final Map<String, List<String>> result = {};
  final seen = <String>{};
  final futures = <Future<void>>[];
  int i = 0;

  for (final card in cards) {
    if (seen.contains(card.scryfallId)) continue;
    seen.add(card.scryfallId);

    if (_oracleTextCache.containsKey(card.scryfallId)) {
      result[card.scryfallId] = _oracleTextCache[card.scryfallId]!;
      continue;
    }

    final delay = Duration(milliseconds: 150 * (i + 1));
    futures.add(
      Future.delayed(delay, () => _fetchOracleTexts(card.scryfallId))
          .then((texts) => result[card.scryfallId] = texts),
    );
    i++;
  }

  await Future.wait(futures);

  return result;
}

String _joinedOracleText(Map<String, List<String>> oracleTexts, Card card) {
  final faces = oracleTexts[card.scryfallId];
  if (faces == null || faces.isEmpty) return '';
  return faces.join('\n');
}

@visibleForTesting
FixingTag detectFixingTag(String oracleText) {
  if (RegExp(r'search.*library.*(land|Forest|Island|Mountain|Plains|Swamp)',
          caseSensitive: false)
      .hasMatch(oracleText)) {
    return FixingTag.landTutor;
  }
  if (RegExp(r'put.*land.*(battlefield|onto the battlefield)',
          caseSensitive: false)
      .hasMatch(oracleText)) {
    return FixingTag.landTutor;
  }
  if (RegExp(r'[Tt]reasure').hasMatch(oracleText)) {
    return FixingTag.treasure;
  }
  if (RegExp(r'\{T\}.*:.*[Aa]dd').hasMatch(oracleText)) {
    return FixingTag.repeatableMana;
  }
  if (RegExp(r'[Aa]dd\s*\{[WUBRGC]').hasMatch(oracleText)) {
    return FixingTag.oneShotMana;
  }
  return FixingTag.none;
}

bool _isRampCard(Card card, String oracleText, Set<String> deckColors) {
  if (card.manaValue > 2) return false;

  final tag = detectFixingTag(oracleText);
  switch (tag) {
    case FixingTag.landTutor:
    case FixingTag.repeatableMana:
    case FixingTag.treasure:
      final fixColors = _getFixedColors(card, oracleText, deckColors, tag);
      return fixColors.intersection(deckColors).isNotEmpty;
    default:
      return false;
  }
}

@visibleForTesting
double getFixingWeight(FixingTag tag) {
  switch (tag) {
    case FixingTag.landTutor:
      return 1.0;
    case FixingTag.repeatableMana:
      return 0.75;
    case FixingTag.treasure:
    case FixingTag.oneShotMana:
      return 0.50;
    default:
      return 0.0;
  }
}

Set<String> _parseProducedMana(String producedMana) {
  final Set<String> colors = {};
  for (final entry in _colorCharToName.entries) {
    if (producedMana.contains(entry.key)) {
      colors.add(entry.value);
    }
  }
  return colors;
}

Set<String> _getFixedColors(
  Card card,
  String oracleText,
  Set<String> deckColors,
  FixingTag tag,
) {
  switch (tag) {
    case FixingTag.landTutor:
    case FixingTag.treasure:
      return deckColors;
    case FixingTag.repeatableMana:
    case FixingTag.oneShotMana:
      if (card.producedMana != null && card.producedMana!.isNotEmpty) {
        return _parseProducedMana(card.producedMana!);
      }
      return {};
    default:
      return {};
  }
}

List<String> _getDeckColors(List<Card> nonLands) {
  final Set<String> colors = {};
  for (final card in nonLands) {
    if (card.manaCost == null) continue;
    for (final entry in _colorCharToName.entries) {
      if (card.manaCost!.contains('{${entry.key}}')) {
        colors.add(entry.value);
      }
    }
  }
  return colors.toList();
}

int _countRamp(
  List<Card> nonLands,
  Set<String> deckColors,
  Map<String, List<String>> oracleTexts,
) {
  int count = 0;
  for (final card in nonLands) {
    final oracleText = _joinedOracleText(oracleTexts, card);
    if (_isRampCard(card, oracleText, deckColors)) {
      count++;
    }
  }
  return count;
}

int _countColoredPips(String manaCost, String colorChar) {
  final pattern = '{$colorChar}';
  int count = 0;
  int index = 0;
  while ((index = manaCost.indexOf(pattern, index)) != -1) {
    count++;
    index += pattern.length;
  }
  return count;
}

Map<String, double> _computeWeightedPips(List<Card> nonLands) {
  final Map<String, double> pips = {
    for (final name in _colorCharToName.values) name: 0.0,
  };

  for (final card in nonLands) {
    if (card.manaCost == null) continue;

    double weight;
    if (card.manaValue <= 2) {
      weight = 2.5;
    } else if (card.manaValue == 3) {
      weight = 1.5;
    } else if (card.manaValue == 4) {
      weight = 1.0;
    } else {
      weight = 0.75;
    }

    for (final entry in _colorCharToName.entries) {
      final pipCount = _countColoredPips(card.manaCost!, entry.key);
      if (pipCount > 0) {
        pips[entry.value] = pips[entry.value]! + pipCount * weight;
      }
    }
  }

  return pips;
}

Map<String, double> _computeVirtualFixing(
  List<Card> nonLands,
  Set<String> deckColors,
  Map<String, List<String>> oracleTexts,
) {
  final Map<String, double> fixing = {
    for (final color in deckColors) color: 0.0,
  };

  for (final card in nonLands) {
    final oracleText = _joinedOracleText(oracleTexts, card);
    final tag = detectFixingTag(oracleText);
    if (tag == FixingTag.none) continue;

    final weight = getFixingWeight(tag);
    final fixColors = _getFixedColors(card, oracleText, deckColors, tag);

    for (final color in fixColors.intersection(deckColors)) {
      fixing[color] = (fixing[color] ?? 0.0) + weight;
    }
  }

  return fixing;
}

Map<String, int> _nonBasicLandSourcesByColor(
  List<Card> nonBasicLands,
  List<String> deckColors,
  Map<String, List<String>> oracleTexts,
) {
  final Map<String, int> sources = {
    for (final color in deckColors) color: 0,
  };

  for (final land in nonBasicLands) {
    if (land.producedMana != null && land.producedMana!.isNotEmpty) {
      final prodColors = _parseProducedMana(land.producedMana!);
      for (final color in prodColors) {
        if (sources.containsKey(color)) {
          sources[color] = sources[color]! + 1;
        }
      }
      continue;
    }

    final oracleText = _joinedOracleText(oracleTexts, land);
    if (oracleText.isEmpty) continue;

    final tag = detectFixingTag(oracleText);
    if (tag != FixingTag.landTutor) continue;

    final specificTypes = <String>[];
    if (oracleText.contains('Plains')) specificTypes.add('White');
    if (oracleText.contains('Island')) specificTypes.add('Blue');
    if (oracleText.contains('Swamp')) specificTypes.add('Black');
    if (oracleText.contains('Mountain')) specificTypes.add('Red');
    if (oracleText.contains('Forest')) specificTypes.add('Green');

    if (specificTypes.isNotEmpty) {
      for (final color in specificTypes) {
        if (sources.containsKey(color)) {
          sources[color] = sources[color]! + 1;
        }
      }
    } else {
      for (final color in deckColors) {
        sources[color] = sources[color]! + 1;
      }
    }
  }

  return sources;
}

Map<String, int> _allocateBasics(
  int B,
  Map<String, double> weightedPips,
  Map<String, double> virtualFixing,
  List<String> deckColors,
) {
  if (deckColors.isEmpty || B <= 0) {
    return {for (final color in deckColors) color: 0};
  }

  double totalWeighted = 0;
  for (final color in deckColors) {
    totalWeighted += weightedPips[color] ?? 0;
  }

  if (totalWeighted == 0) {
    return {for (final color in deckColors) color: 0};
  }

  final Map<String, int> basics = {};
  int allocated = 0;

  for (final color in deckColors) {
    final weight = weightedPips[color] ?? 0;
    final fix = virtualFixing[color] ?? 0;
    final raw = B * weight / totalWeighted - fix;
    final count = max(0, raw.round());
    basics[color] = count;
    allocated += count;
  }

  while (allocated < B && deckColors.isNotEmpty) {
    final largestKey = deckColors.reduce(
      (a, b) => (weightedPips[a] ?? 0) >= (weightedPips[b] ?? 0) ? a : b,
    );
    basics[largestKey] = (basics[largestKey] ?? 0) + 1;
    allocated++;
  }

  while (allocated > B) {
    int largestVal = 0;
    String? largestKey;
    for (final entry in basics.entries) {
      if (entry.value > largestVal) {
        largestVal = entry.value;
        largestKey = entry.key;
      }
    }
    if (largestKey != null) {
      basics[largestKey] = largestVal - 1;
      allocated--;
    } else {
      break;
    }
  }

  return basics;
}

@visibleForTesting
int requiredFloor(int mv, int pipCount) {
  if (pipCount == 0) return 0;
  if (mv == 1 && pipCount == 1) return 9;
  if (mv == 2 && pipCount >= 2) return 11;
  if (mv == 2 && pipCount == 1) return 8;
  if (mv == 3 && pipCount == 1) return 7;
  if (mv == 3 && pipCount >= 2) return 10;
  if (mv >= 4 && pipCount == 1) return 8;
  if (mv >= 4 && pipCount >= 2) return 10;
  return 8;
}

Map<String, int> _applyFloorCheck(
  Map<String, int> basics,
  List<Card> nonLands,
  Map<String, int> nonBasicSourcesByColor,
  Map<String, double> virtualFixing,
  List<String> deckColors,
) {
  if (deckColors.length < 2) return Map.of(basics);

  final floors = <String, int>{};
  for (final color in deckColors) {
    int maxFloor = 0;
    final colorChar = _colorCharToName.entries
        .firstWhere((e) => e.value == color)
        .key;
    for (final card in nonLands) {
      if (card.manaCost == null) continue;
      final pipCount = _countColoredPips(card.manaCost!, colorChar);
      if (pipCount == 0) continue;
      final floor = requiredFloor(card.manaValue, pipCount);
      if (floor > maxFloor) maxFloor = floor;
    }
    floors[color] = maxFloor;
  }

  final result = Map.of(basics);

  for (final color in deckColors) {
    if (floors[color] == 0) continue;

    final fixingRounded = (virtualFixing[color] ?? 0.0).round();
    final sVirt = (result[color] ?? 0) +
        (nonBasicSourcesByColor[color] ?? 0) +
        fixingRounded;

    final deficit = floors[color]! - sVirt;
    if (deficit <= 0) continue;

    for (final otherColor in deckColors) {
      if (otherColor == color) continue;
      if (deficit <= 0) break;

      final available = result[otherColor] ?? 0;
      if (available <= 0) continue;

      final shift = min(deficit, available);
      result[color] = (result[color] ?? 0) + shift;
      result[otherColor] = available - shift;
    }
  }

  return result;
}

Future<BasicLandResult> calculateBasicLands(Deck deck) async {
  final nonLands = deck.cards
      .where((c) => c.type != 'Land')
      .toList();
  final nonBasicLands = deck.cards
      .where((c) => c.type == 'Land' && !_basicLandNames.contains(c.name))
      .toList();

  final cardsToFetch = <Card>[
    ...nonLands,
    ...nonBasicLands.where((l) => (l.producedMana ?? '').isEmpty),
  ];

  final oracleTexts = await _fetchAllOracleTexts(cardsToFetch);

  return calculateBasicLandsWithOracleTexts(deck, oracleTexts);
}

@visibleForTesting
BasicLandResult calculateBasicLandsWithOracleTexts(
  Deck deck,
  Map<String, List<String>> oracleTexts,
) {
  final nonLands = deck.cards
      .where((c) => c.type != 'Land')
      .toList();
  final nonBasicLands = deck.cards
      .where((c) => c.type == 'Land' && !_basicLandNames.contains(c.name))
      .toList();

  final deckColors = _getDeckColors(nonLands);
  final deckColorSet = Set.of(deckColors);

  final rampCount = _countRamp(nonLands, deckColorSet, oracleTexts);
  final L = 17 - (rampCount ~/ 2);
  final D = nonBasicLands.length;
  final B = max(0, L - D);

  final weightedPips = _computeWeightedPips(nonLands);
  final virtualFixing = _computeVirtualFixing(nonLands, deckColorSet, oracleTexts);
  final basics = _allocateBasics(B, weightedPips, virtualFixing, deckColors);
  final nonBasicSources = _nonBasicLandSourcesByColor(
    nonBasicLands,
    deckColors,
    oracleTexts,
  );
  final finalBasics = _applyFloorCheck(
    basics,
    nonLands,
    nonBasicSources,
    virtualFixing,
    deckColors,
  );

  return BasicLandResult(
    basics: finalBasics,
    totalLands: L,
    basicLandSlots: B,
    nonBasicLandCount: D,
    rampCount: rampCount,
    weightedPips: weightedPips,
    virtualFixing: virtualFixing,
  );
}

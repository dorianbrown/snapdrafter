import 'dart:math';

import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/deck.dart';
import '../data/models/card.dart';

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

String fixingTagLabel(FixingTag tag) {
  switch (tag) {
    case FixingTag.landTutor: return 'land tutor';
    case FixingTag.repeatableMana: return 'mana rock / dork';
    case FixingTag.treasure: return 'treasure';
    case FixingTag.oneShotMana: return 'one-shot mana';
    case FixingTag.none: return '';
  }
}

class FixingCard {
  final String name;
  final FixingTag tag;
  final double weight;
  final Set<String> colors;

  const FixingCard({
    required this.name,
    required this.tag,
    required this.weight,
    required this.colors,
  });
}

class NonBasicLandSource {
  final String name;
  final Set<String> colors;

  const NonBasicLandSource({required this.name, required this.colors});
}

class BasicLandResult {
  final Map<String, int> basics;
  final int totalLands;
  final int basicLandSlots;
  final int nonBasicLandCount;
  final int rampCount;
  final Map<String, double> weightedPips;
  final Map<String, double> virtualFixing;
  final List<FixingCard> fixingCards;
  final List<NonBasicLandSource> nonBasicLandSources;

  const BasicLandResult({
    required this.basics,
    required this.totalLands,
    required this.basicLandSlots,
    required this.nonBasicLandCount,
    required this.rampCount,
    required this.weightedPips,
    required this.virtualFixing,
    required this.fixingCards,
    required this.nonBasicLandSources,
  });
}

Map<String, List<String>> _buildOracleTexts(List<Card> cards) {
  final Map<String, List<String>> result = {};
  for (final card in cards) {
    if (card.oracleText != null && card.oracleText!.isNotEmpty) {
      result[card.scryfallId] = [card.oracleText!];
    }
  }
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

({Map<String, double> totals, List<FixingCard> cards}) _computeVirtualFixing(
  List<Card> nonLands,
  Set<String> deckColors,
  Map<String, List<String>> oracleTexts,
) {
  final Map<String, double> fixing = {
    for (final color in deckColors) color: 0.0,
  };
  final List<FixingCard> fixingCards = [];

  for (final card in nonLands) {
    final oracleText = _joinedOracleText(oracleTexts, card);
    final tag = detectFixingTag(oracleText);
    if (tag == FixingTag.none) continue;

    final weight = getFixingWeight(tag);
    final fixColors = _getFixedColors(card, oracleText, deckColors, tag);
    final intersection = fixColors.intersection(deckColors);

    for (final color in intersection) {
      fixing[color] = (fixing[color] ?? 0.0) + weight;
    }

    if (intersection.isNotEmpty) {
      fixingCards.add(FixingCard(
        name: card.name,
        tag: tag,
        weight: weight,
        colors: intersection,
      ));
    }
  }

  return (totals: fixing, cards: fixingCards);
}

({Map<String, int> counts, List<NonBasicLandSource> sources}) _nonBasicLandSourcesByColor(
  List<Card> nonBasicLands,
  List<String> deckColors,
  Map<String, List<String>> oracleTexts,
) {
  final Map<String, int> sources = {
    for (final color in deckColors) color: 0,
  };
  final List<NonBasicLandSource> landSources = [];

  for (final land in nonBasicLands) {
    Set<String> prodColors;

    if (land.producedMana != null && land.producedMana!.isNotEmpty) {
      prodColors = _parseProducedMana(land.producedMana!);
    } else {
      final oracleText = _joinedOracleText(oracleTexts, land);
      if (oracleText.isEmpty) continue;

      final tag = detectFixingTag(oracleText);
      if (tag != FixingTag.landTutor) continue;

      final specificTypes = <String>{};
      if (oracleText.contains('Plains')) specificTypes.add('White');
      if (oracleText.contains('Island')) specificTypes.add('Blue');
      if (oracleText.contains('Swamp')) specificTypes.add('Black');
      if (oracleText.contains('Mountain')) specificTypes.add('Red');
      if (oracleText.contains('Forest')) specificTypes.add('Green');

      prodColors = specificTypes.isNotEmpty ? specificTypes : Set.of(deckColors);
    }

    for (final color in prodColors) {
      if (sources.containsKey(color)) {
        sources[color] = sources[color]! + 1;
      }
    }

    final intersection = prodColors.where((c) => deckColors.contains(c)).toSet();
    if (intersection.isNotEmpty) {
      landSources.add(NonBasicLandSource(name: land.name, colors: intersection));
    }
  }

  return (counts: sources, sources: landSources);
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
  if (mv >= 4 && pipCount == 1) return 6;
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
  final minBasics = <String, int>{};
  final deficit = <String, int>{};
  final surplus = <String, int>{};
  int totalDeficit = 0;
  int totalSurplus = 0;

  for (final color in deckColors) {
    final fixingRounded = (virtualFixing[color] ?? 0.0).round();
    final needed = max(0, (floors[color] ?? 0) -
        (nonBasicSourcesByColor[color] ?? 0) -
        fixingRounded);
    minBasics[color] = needed;
    final current = result[color] ?? 0;
    if (current < needed) {
      deficit[color] = needed - current;
      totalDeficit += deficit[color]!;
    } else if (current > needed) {
      surplus[color] = current - needed;
      totalSurplus += surplus[color]!;
    }
  }

  if (totalDeficit == 0 || totalSurplus == 0) return result;

  final distributable = min(totalDeficit, totalSurplus);

  final shares = <String, double>{};
  for (final entry in deficit.entries) {
    shares[entry.key] = distributable * entry.value / totalDeficit;
  }

  final shareInts = <String, int>{};
  int assigned = 0;
  for (final entry in deficit.entries) {
    shareInts[entry.key] = shares[entry.key]!.floor();
    assigned += shareInts[entry.key]!;
  }

  if (assigned < distributable) {
    final remainder = deficit.keys.toList()
      ..sort((a, b) =>
          (shares[b]! - shareInts[b]!).compareTo(shares[a]! - shareInts[a]!));
    for (final color in remainder) {
      if (assigned >= distributable) break;
      shareInts[color] = shareInts[color]! + 1;
      assigned++;
    }
  }

  final takes = <String, double>{};
  for (final entry in surplus.entries) {
    takes[entry.key] = distributable * entry.value / totalSurplus;
  }

  final takeInts = <String, int>{};
  int taken = 0;
  for (final entry in surplus.entries) {
    takeInts[entry.key] = takes[entry.key]!.floor();
    taken += takeInts[entry.key]!;
  }

  if (taken < distributable) {
    final remainder = surplus.keys.toList()
      ..sort((a, b) =>
          (takes[b]! - takeInts[b]!).compareTo(takes[a]! - takeInts[a]!));
    for (final color in remainder) {
      if (taken >= distributable) break;
      takeInts[color] = takeInts[color]! + 1;
      taken++;
    }
  }

  for (final entry in shareInts.entries) {
    result[entry.key] = (result[entry.key] ?? 0) + entry.value;
  }
  for (final entry in takeInts.entries) {
    result[entry.key] = (result[entry.key] ?? 0) - entry.value;
  }

  return result;
}

Future<BasicLandResult> calculateBasicLands(Deck deck) async {
  final prefs = await SharedPreferences.getInstance();
  final debug = prefs.getBool("debug_enabled") ?? false;

  final cardsToSearch = deck.cards
      .where((c) => c.type != 'Land' ||
          (c.type == 'Land' && !_basicLandNames.contains(c.name) &&
              (c.producedMana ?? '').isEmpty))
      .toList();

  final oracleTexts = _buildOracleTexts(cardsToSearch);

  return calculateBasicLandsWithOracleTexts(deck, oracleTexts, debug: debug);
}

@visibleForTesting
BasicLandResult calculateBasicLandsWithOracleTexts(
  Deck deck,
  Map<String, List<String>> oracleTexts, {
  bool debug = false,
}) {
  final nonLands = deck.cards
      .where((c) => c.type != 'Land')
      .toList();
  final nonBasicLands = deck.cards
      .where((c) => c.type == 'Land' && !_basicLandNames.contains(c.name))
      .toList();

  if (debug) {
    print('=== LAND CALCULATOR DEBUG ===');
    print('Deck total cards: ${deck.cards.length}');
    print('Non-land cards: ${nonLands.length}');
    print('Non-basic lands: ${nonBasicLands.length}');
    print('');

    print('--- Per-card Pip Analysis ---');
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
      final parts = <String>[];
      for (final entry in _colorCharToName.entries) {
        final pipCount = _countColoredPips(card.manaCost!, entry.key);
        if (pipCount > 0) {
          parts.add('${entry.value}=${pipCount} pip(s) x weight $weight = ${pipCount * weight}');
        }
      }
      print('  ${card.name} (MV=${card.manaValue}, cost=${card.manaCost}) -> ${parts.join(", ")}');
    }
    for (final card in nonLands.where((c) => c.manaCost == null)) {
      print('  ${card.name} (MV=${card.manaValue}, cost=NULL) -> no colored pips');
    }
    print('');
  }

  final deckColors = _getDeckColors(nonLands);
  final deckColorSet = Set.of(deckColors);

  if (debug) {
    print('--- Deck Colors ---');
    print('  $deckColors');
    print('');
  }

  final rampCount = _countRamp(nonLands, deckColorSet, oracleTexts);
  final L = 17 - (rampCount ~/ 2);
  final D = nonBasicLands.length;
  final B = max(0, L - D);

  if (debug) {
    print('--- Land Budget ---');
    print('  Ramp cards: $rampCount');
    print('  Total lands (L = 17 - ramp/2): $L');
    print('  Non-basic lands (D): $D');
    print('  Basic land slots (B = L - D): $B');
    print('');
  }

  final weightedPips = _computeWeightedPips(nonLands);

  if (debug) {
    print('--- Weighted Pips ---');
    double totalWeighted = 0;
    for (final color in deckColors) {
      totalWeighted += weightedPips[color] ?? 0;
    }
    for (final color in deckColors) {
      final w = weightedPips[color] ?? 0;
      final pct = totalWeighted > 0 ? (w / totalWeighted * 100).toStringAsFixed(1) : '0.0';
      print('  $color: $w ($pct%)');
    }
    print('');
  }

  final (:totals, :cards) = _computeVirtualFixing(nonLands, deckColorSet, oracleTexts);

  if (debug) {
    print('--- Virtual Fixing ---');
    for (final color in deckColors) {
      final v = totals[color] ?? 0;
      print('  $color: $v');
    }
    for (final card in cards) {
      print('    ${card.name} -> ${fixingTagLabel(card.tag)} (weight=${card.weight}, colors=${card.colors})');
    }
    print('');
  }

  final basics = _allocateBasics(B, weightedPips, totals, deckColors);

  if (debug) {
    print('--- Initial Allocation (_allocateBasics) ---');
    double totalWeighted = 0;
    for (final color in deckColors) {
      totalWeighted += weightedPips[color] ?? 0;
    }
    for (final color in deckColors) {
      final w = weightedPips[color] ?? 0;
      final fix = totals[color] ?? 0;
      final raw = totalWeighted > 0 ? B * w / totalWeighted - fix : 0;
      final count = basics[color] ?? 0;
      print('  $color: weight=$w, fix=$fix, raw=B*(w/$totalWeighted)-fix=$raw, rounded=$count');
    }
    print('');
  }

  final (:counts, :sources) = _nonBasicLandSourcesByColor(
    nonBasicLands,
    deckColors,
    oracleTexts,
  );

  if (debug) {
    print('--- Non-Basic Land Sources by Color ---');
    for (final color in deckColors) {
      final c = counts[color] ?? 0;
      print('  $color: $c sources');
    }
    for (final src in sources) {
      print('    ${src.name} -> ${src.colors}');
    }
    print('');
  }

  final finalBasics = _applyFloorCheck(
    basics,
    nonLands,
    counts,
    totals,
    deckColors,
  );

  if (debug && deckColors.length >= 2) {
    print('--- Floor Check ---');
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

    final minBasics = <String, int>{};
    final deficit = <String, int>{};
    final surplus = <String, int>{};
    for (final color in deckColors) {
      final fixR = (totals[color] ?? 0).round();
      minBasics[color] = max(0, (floors[color] ?? 0) -
          (counts[color] ?? 0) -
          fixR);
      final curr = basics[color] ?? 0;
      final d = minBasics[color]! - curr;
      if (d > 0) {
        deficit[color] = d;
      } else if (d < 0) {
        surplus[color] = -d;
      }
    }

    final totalDeficit = deficit.values.fold<int>(0, (a, b) => a + b);
    final totalSurplus = surplus.values.fold<int>(0, (a, b) => a + b);

    for (final color in deckColors) {
      final floor = floors[color] ?? 0;
      final bas = basics[color] ?? 0;
      final nbs = counts[color] ?? 0;
      final fixR = (totals[color] ?? 0).round();
      final sVirt = bas + nbs + fixR;
      final minB = minBasics[color] ?? 0;
      final def = deficit[color] ?? 0;
      final surp = surplus[color] ?? 0;
      final finalCount = finalBasics[color] ?? 0;
      final shifted = finalCount - bas;
      final status = def > 0 ? 'DEFICIT=$def' : (surp > 0 ? 'SURPLUS=$surp' : 'balanced');
      print('  $color: floor=$floor, minBasics=$minB, sVirt(bas=$bas, nbs=$nbs, fixR=$fixR)=$sVirt, $status, final=$finalCount (shifted ${shifted >= 0 ? '+' : ''}$shifted)');
    }
    if (totalDeficit > 0) {
      print('  -- Proportional distribution: distributable=${min(totalDeficit, totalSurplus)}, totalDeficit=$totalDeficit, totalSurplus=$totalSurplus');
      print('  -- Shares: ${finalBasics.map((k, v) => MapEntry(k, v - (basics[k] ?? 0)))}');
    }
    print('');
  }

  if (debug) {
    print('--- Final Result ---');
    for (final color in deckColors) {
      print('  $color -> ${finalBasics[color] ?? 0} basics');
    }
    print('==========================');
    print('');
  }

  return BasicLandResult(
    basics: finalBasics,
    totalLands: L,
    basicLandSlots: B,
    nonBasicLandCount: D,
    rampCount: rampCount,
    weightedPips: weightedPips,
    virtualFixing: totals,
    fixingCards: cards,
    nonBasicLandSources: sources,
  );
}

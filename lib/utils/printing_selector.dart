/// Pure helpers for selecting card/token artwork during the Scryfall download.
///
/// The bulk "unique_artwork" file contains one entry per unique artwork, so a
/// single card (identified by oracle id) can appear many times. These helpers
/// pick the best Universes Beyond (UB) and best non-UB printing per oracle id.
class PrintingSelector {
  /// Returns true when the Scryfall entry is a Universes Beyond printing.
  static bool isUniversesBeyond(Map<dynamic, dynamic> val) {
    final promoTypes = val['promo_types'];
    return promoTypes is List && promoTypes.contains('universesbeyond');
  }

  /// Extracts the "normal" image URI from a Scryfall entry, using the first
  /// face for double-faced cards. Returns null when no image is available.
  static String? extractImageUri(Map<dynamic, dynamic> val) {
    final imageUris = val['image_uris'];
    if (imageUris is Map) {
      return imageUris['normal'] as String?;
    }
    final faces = val['card_faces'];
    if (faces is List && faces.isNotEmpty && faces.first is Map) {
      final faceUris = (faces.first as Map)['image_uris'];
      if (faceUris is Map) {
        return faceUris['normal'] as String?;
      }
    }
    return null;
  }

  /// Frame effects that mark a printing as a special/alternate frame. Regular
  /// treatments such as `legendary`, `enchantment`, `snow` or the DFC
  /// variants are deliberately not included.
  static const List<String> _specialFrameEffects = [
    'borderless',
    'showcase',
    'extendedart',
    'fullart',
    'inverted',
    'etched',
    'shatteredglass',
    'colorshifted',
    'miracle',
  ];

  /// Set types of special products: Secret Lair Drop (sld/slu/slc), Secret
  /// Lair Promo (slp), Showcase Planes (pssc), 30th Anniversary (30a) and the
  /// premium reprint products (expeditions, invocations, Special Guests...).
  static const List<String> _specialSetTypes = [
    'box',
    'promo',
    'memorabilia',
    'masterpiece',
  ];

  /// Promo types that mark a printing as a special/promo variant (booster fun
  /// variants, promo pack inserts, etc.).
  static const List<String> _specialPromoTypes = [
    'boosterfun',
    'promopack',
  ];

  /// Returns true for special printings (Secret Lair drops, promos, alternate
  /// frames, etc.). These are only preferred when no regular printing of the
  /// card exists.
  static bool isSpecialPrinting(Map<dynamic, dynamic> val) {
    if (val['promo'] == true) return true;
    final frameEffects = val['frame_effects'];
    if (frameEffects is List &&
        frameEffects.any((f) => _specialFrameEffects.contains(f))) {
      return true;
    }
    if (val['full_art'] == true || val['textless'] == true) return true;
    if (_specialSetTypes.contains(val['set_type'])) return true;
    final promoTypes = val['promo_types'];
    if (promoTypes is List &&
        promoTypes.any((p) => _specialPromoTypes.contains(p))) {
      return true;
    }
    return false;
  }

  /// Builds a compact record of a printing, retaining only the fields needed
  /// for deduplication and comparison. Used instead of keeping the full
  /// Scryfall JSON of every artwork in memory.
  static Map<String, dynamic> entryRecord(Map<dynamic, dynamic> val) => {
    'scryfall_id': val['id'],
    'image_uri': extractImageUri(val),
    'released_at': val['released_at'],
    'special': isSpecialPrinting(val),
    'english': val['lang'] == 'en',
    'is_ub': isUniversesBeyond(val),
    'set_type': val['set_type'],
    'digital': val['digital'] == true,
    'set_name': val['set_name'],
  };

  static const List<String> _validTypes = [
    "Creature",
    "Artifact",
    "Enchantment",
    "Land",
    "Instant",
    "Sorcery",
    "Planeswalker",
    "Battle"
  ];

  /// Extracts the oracle-level fields that are identical across all printings
  /// of a card, from the first entry seen for each oracle id.
  ///
  /// Null-safe: some layouts (e.g. "prepare") have card faces without a
  /// `colors` field, so the card-level colors are used as a fallback.
  static Map<String, dynamic> oracleFields(Map<dynamic, dynamic> val) {
    String cardType = "";
    final typeLine = (val['type_line'] as String?) ?? "";
    for (final type in _validTypes) {
      if (typeLine.contains(type)) {
        cardType = type;
        break;
      }
    }

    String colors = "";
    String? manaCost;
    String? producedMana;
    String? oracleText;

    final faces = val['card_faces'];
    if (faces is List && faces.isNotEmpty) {
      final firstFace = faces.first as Map;
      colors = (firstFace['colors'] as List?)?.join("") ??
          (val['colors'] as List?)?.join("") ??
          "";
      manaCost = firstFace['mana_cost'] ?? val['mana_cost'];
      producedMana = firstFace['produced_mana'] ??
          (faces.length > 1 ? (faces[1] as Map)['produced_mana'] : null);
      final faceTexts = faces
          .map((f) => ((f as Map)['oracle_text'] ?? "").toString())
          .where((t) => t.isNotEmpty)
          .toList();
      oracleText = faceTexts.isNotEmpty ? faceTexts.join("\n") : null;
    } else {
      colors = (val['colors'] as List?)?.join("") ?? "";
      manaCost = val['mana_cost'];
      producedMana = (val['produced_mana'] as List?)?.join("");
      oracleText = val['oracle_text'];
      if (oracleText == '') {
        oracleText = null;
      }
    }

    return {
      'name': val['name'],
      'title': val['name'].split(" // ")[0],
      'type': cardType,
      'colors': colors,
      'mana_cost': manaCost,
      'mana_value': val['cmc'].toInt(),
      'produced_mana': producedMana,
      'oracle_text': oracleText,
    };
  }

  /// Compares a raw Scryfall entry against a stored compact record (see
  /// [entryRecord]) using the same ordering as [compareEntries], without
  /// allocating a record for the challenger. Returns a negative value when
  /// [val] is the better choice.
  static int compareRawToRecord(
      Map<dynamic, dynamic> val, Map<dynamic, dynamic> record) {
    final tieBreak = _compareTieBreaks(val['lang'] == 'en',
        isSpecialPrinting(val), record['english'] == true, record['special'] == true);
    if (tieBreak != 0) return tieBreak;

    final ubCompare = (isUniversesBeyond(val) ? 1 : 0) -
        (record['is_ub'] == true ? 1 : 0);
    if (ubCompare != 0) return ubCompare;

    final releaseCompare = (record['released_at'] as String)
        .compareTo(val['released_at'] as String);
    if (releaseCompare != 0) return releaseCompare;

    return 0;
  }

  /// Compares two compact printing records (see [entryRecord]).
  /// Returns a negative value when [a] is the better choice.
  ///
  /// Ordering: regular printings before special printings (Secret Lair
  /// drops, promos, alternate frames), then English before other languages,
  /// then non-Universes Beyond, then newest release date.
  static int compareEntries(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    final tieBreak = _compareTieBreaks(a['english'] == true, a['special'] == true,
        b['english'] == true, b['special'] == true);
    if (tieBreak != 0) return tieBreak;

    final ubCompare = (a['is_ub'] == true ? 1 : 0) - (b['is_ub'] == true ? 1 : 0);
    if (ubCompare != 0) return ubCompare;

    final releaseCompare =
        (b['released_at'] as String).compareTo(a['released_at'] as String);
    if (releaseCompare != 0) return releaseCompare;

    return 0;
  }

  /// Compares a raw Scryfall entry against a stored compact record using the
  /// same ordering as [compareFirstPrintingEntries], without allocating a
  /// record for the challenger. Returns a negative value when [val] is the
  /// better choice.
  static int compareFirstPrintingRawToRecord(
      Map<dynamic, dynamic> val, Map<dynamic, dynamic> record) {
    final releaseCompare = (val['released_at'] as String)
        .compareTo(record['released_at'] as String);
    if (releaseCompare != 0) return releaseCompare;

    final tieBreak = _compareTieBreaks(val['lang'] == 'en',
        isSpecialPrinting(val), record['english'] == true, record['special'] == true);
    if (tieBreak != 0) return tieBreak;

    return (isUniversesBeyond(val) ? 1 : 0) -
        (record['is_ub'] == true ? 1 : 0);
  }

  /// Compares two compact printing records for the first-printing selection.
  /// Returns a negative value when [a] is the better choice.
  ///
  /// Ordering: earliest release date, then regular printings before special
  /// printings, then English before other languages, then non-Universes
  /// Beyond.
  static int compareFirstPrintingEntries(
      Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    final releaseCompare = (a['released_at'] as String)
        .compareTo(b['released_at'] as String);
    if (releaseCompare != 0) return releaseCompare;

    final tieBreak = _compareTieBreaks(a['english'] == true, a['special'] == true,
        b['english'] == true, b['special'] == true);
    if (tieBreak != 0) return tieBreak;

    return (a['is_ub'] == true ? 1 : 0) - (b['is_ub'] == true ? 1 : 0);
  }

  /// Shared preference tie-breaks used by all comparators: regular before
  /// special, English before other languages, non-UB before UB. Returns a
  /// negative value when [a] is the better choice.
  static int _compareTieBreaks(bool aEnglish, bool aSpecial, bool bEnglish,
      bool bSpecial) {
    final specialCompare = (aSpecial ? 1 : 0) - (bSpecial ? 1 : 0);
    if (specialCompare != 0) return specialCompare;

    final englishCompare = (aEnglish ? 0 : 1) - (bEnglish ? 0 : 1);
    if (englishCompare != 0) return englishCompare;

    return 0;
  }
}

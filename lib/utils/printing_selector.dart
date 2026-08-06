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

  /// Builds a compact record of a printing, retaining only the fields needed
  /// for deduplication and comparison. Used instead of keeping the full
  /// Scryfall JSON of every artwork in memory.
  static Map<String, dynamic> entryRecord(Map<dynamic, dynamic> val) => {
    'scryfall_id': val['id'],
    'image_uri': extractImageUri(val),
    'released_at': val['released_at'],
    'promo': val['promo'] == true,
    'frame_effects': (val['frame_effects'] as List?) ?? const [],
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
    final releaseCompare = (record['released_at'] as String)
        .compareTo(val['released_at'] as String);
    if (releaseCompare != 0) return releaseCompare;

    final promoCompare = (val['promo'] == true ? 1 : 0) -
        (record['promo'] == true ? 1 : 0);
    if (promoCompare != 0) return promoCompare;

    final valHasFrameEffects =
        ((val['frame_effects'] as List?)?.isNotEmpty ?? false) ? 1 : 0;
    final recordHasFrameEffects =
        ((record['frame_effects'] as List?)?.isNotEmpty ?? false) ? 1 : 0;
    if (valHasFrameEffects != recordHasFrameEffects) {
      return valHasFrameEffects - recordHasFrameEffects;
    }

    return (isUniversesBeyond(val) ? 1 : 0) -
        (record['is_ub'] == true ? 1 : 0);
  }

  /// Compares two compact printing records (see [entryRecord]).
  /// Returns a negative value when [a] is the better choice.
  ///
  /// Ordering: newest release date, then non-promo, then no special frame
  /// effects (borderless, showcase, etc.), then non-Universes Beyond.
  static int compareEntries(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    final releaseCompare =
        (b['released_at'] as String).compareTo(a['released_at'] as String);
    if (releaseCompare != 0) return releaseCompare;

    final promoCompare =
        (a['promo'] == true ? 1 : 0) - (b['promo'] == true ? 1 : 0);
    if (promoCompare != 0) return promoCompare;

    final aHasFrameEffects =
        ((a['frame_effects'] as List?)?.isNotEmpty ?? false) ? 1 : 0;
    final bHasFrameEffects =
        ((b['frame_effects'] as List?)?.isNotEmpty ?? false) ? 1 : 0;
    if (aHasFrameEffects != bHasFrameEffects) {
      return aHasFrameEffects - bHasFrameEffects;
    }

    return (a['is_ub'] == true ? 1 : 0) - (b['is_ub'] == true ? 1 : 0);
  }
}

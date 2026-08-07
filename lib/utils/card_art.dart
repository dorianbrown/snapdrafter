import 'package:flutter/foundation.dart';

import '/data/models/card.dart';

/// Global preference for which artwork is displayed for cards and tokens.
///
/// When the user prefers original printings, [resolveCardImageUri] returns
/// the first printing's image URI when one is stored, falling back to the
/// default image URI otherwise.
class CardArtPreferences {
  static const String prefKey = 'prefer_original_art';

  static final ValueNotifier<bool> preferOriginalArt = ValueNotifier(false);

  /// Corner radius of standard printings, matching the physical cards.
  static const double standardCornerRadius = 25;

  /// Corner radius of Alpha (LEA) and Beta (LEB) printings, whose physical
  /// cards use a different corner cut than later printings.
  static const double legacyCornerRadius = 35;

  /// Set codes printed with the legacy corner cut.
  static const Set<String> legacyFrameSets = {'lea', 'leb'};

  /// Returns true when [setCode] belongs to a printing with the legacy
  /// (Alpha/Beta) corner cut.
  static bool isLegacyFrame(String? setCode) =>
      setCode != null && legacyFrameSets.contains(setCode);

  /// Returns [firstPrintingUri] when the preference is enabled and a first
  /// printing image is available, otherwise [defaultUri].
  static String? resolveCardImageUri(String? defaultUri, String? firstPrintingUri) {
    if (preferOriginalArt.value &&
        firstPrintingUri != null &&
        firstPrintingUri.isNotEmpty) {
      return firstPrintingUri;
    }
    return defaultUri;
  }

  /// Returns the set code of the printing whose artwork is currently
  /// resolved, mirroring [resolveCardImageUri].
  static String? resolvedSetCode(String? imageSetCode, String? firstPrintingSetCode) {
    if (preferOriginalArt.value &&
        firstPrintingSetCode != null &&
        firstPrintingSetCode.isNotEmpty) {
      return firstPrintingSetCode;
    }
    return imageSetCode;
  }

  /// Returns the corner radius for the printing currently resolved between
  /// [imageSetCode] and [firstPrintingSetCode], mirroring [resolveCardImageUri]:
  /// [legacyCornerRadius] for Alpha/Beta printings, otherwise
  /// [standardCornerRadius].
  static double cornerRadiusFor(String? imageSetCode, String? firstPrintingSetCode) =>
      isLegacyFrame(resolvedSetCode(imageSetCode, firstPrintingSetCode))
          ? legacyCornerRadius
          : standardCornerRadius;

  /// Returns the corner radius for the artwork currently resolved for
  /// [card].
  static double cornerRadius(Card card) =>
      cornerRadiusFor(card.imageSetCode, card.firstPrintingSetCode);
}

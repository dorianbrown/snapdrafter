import 'package:flutter/foundation.dart';

/// Global preference for which artwork is displayed for cards and tokens.
///
/// When the user prefers original printings, [resolveCardImageUri] returns
/// the first printing's image URI when one is stored, falling back to the
/// default image URI otherwise.
class CardArtPreferences {
  static const String prefKey = 'prefer_original_art';

  static final ValueNotifier<bool> preferOriginalArt = ValueNotifier(false);

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
}

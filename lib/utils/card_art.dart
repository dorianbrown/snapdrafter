import 'package:flutter/foundation.dart';

/// Global preference for which artwork is displayed for cards and tokens.
///
/// When the user prefers non-Universes Beyond art, [resolveCardImageUri]
/// returns the non-UB printing's image URI when one is stored, falling back
/// to the default image URI otherwise.
class CardArtPreferences {
  static const String prefKey = 'prefer_non_ub_art';

  static final ValueNotifier<bool> preferNonUbArt = ValueNotifier(false);

  /// Returns [nonUbUri] when the preference is enabled and a non-UB printing
  /// is available, otherwise [defaultUri].
  static String? resolveCardImageUri(String? defaultUri, String? nonUbUri) {
    if (preferNonUbArt.value && nonUbUri != null && nonUbUri.isNotEmpty) {
      return nonUbUri;
    }
    return defaultUri;
  }
}

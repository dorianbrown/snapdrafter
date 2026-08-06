import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/card_art.dart';

void main() {
  tearDown(() {
    CardArtPreferences.preferNonUbArt.value = false;
  });

  group('CardArtPreferences.resolveCardImageUri', () {
    test('returns default URI when preference is off', () {
      CardArtPreferences.preferNonUbArt.value = false;
      expect(
        CardArtPreferences.resolveCardImageUri(
            'https://default.jpg', 'https://non-ub.jpg'),
        'https://default.jpg',
      );
    });

    test('returns non-UB URI when preference is on and available', () {
      CardArtPreferences.preferNonUbArt.value = true;
      expect(
        CardArtPreferences.resolveCardImageUri(
            'https://default.jpg', 'https://non-ub.jpg'),
        'https://non-ub.jpg',
      );
    });

    test('falls back to default URI when no non-UB printing exists', () {
      CardArtPreferences.preferNonUbArt.value = true;
      expect(
        CardArtPreferences.resolveCardImageUri('https://default.jpg', null),
        'https://default.jpg',
      );
    });

    test('falls back to default URI when non-UB URI is empty', () {
      CardArtPreferences.preferNonUbArt.value = true;
      expect(
        CardArtPreferences.resolveCardImageUri('https://default.jpg', ''),
        'https://default.jpg',
      );
    });

    test('returns null when only nulls are given', () {
      CardArtPreferences.preferNonUbArt.value = true;
      expect(CardArtPreferences.resolveCardImageUri(null, null), null);
    });
  });
}

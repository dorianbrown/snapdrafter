import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/card_art.dart';

void main() {
  tearDown(() {
    CardArtPreferences.preferOriginalArt.value = false;
  });

  group('CardArtPreferences.resolveCardImageUri', () {
    test('returns default URI when preference is off', () {
      CardArtPreferences.preferOriginalArt.value = false;
      expect(
        CardArtPreferences.resolveCardImageUri(
            'https://default.jpg', 'https://first.jpg'),
        'https://default.jpg',
      );
    });

    test('returns first printing URI when preference is on and available', () {
      CardArtPreferences.preferOriginalArt.value = true;
      expect(
        CardArtPreferences.resolveCardImageUri(
            'https://default.jpg', 'https://first.jpg'),
        'https://first.jpg',
      );
    });

    test('falls back to default URI when no first printing exists', () {
      CardArtPreferences.preferOriginalArt.value = true;
      expect(
        CardArtPreferences.resolveCardImageUri('https://default.jpg', null),
        'https://default.jpg',
      );
    });

    test('falls back to default URI when first printing URI is empty', () {
      CardArtPreferences.preferOriginalArt.value = true;
      expect(
        CardArtPreferences.resolveCardImageUri('https://default.jpg', ''),
        'https://default.jpg',
      );
    });

    test('returns null when only nulls are given', () {
      CardArtPreferences.preferOriginalArt.value = true;
      expect(CardArtPreferences.resolveCardImageUri(null, null), null);
    });
  });
}

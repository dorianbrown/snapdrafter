import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/dropdown_position.dart';

void main() {
  const screen = Size(400, 800);

  Rect? place(Offset caret,
      {double caretHeight = 16,
      double keyboard = 0,
      Size? panel,
      Size? screenSize,
      double minPanelHeight = 52}) {
    return dropdownPlacement(
      caretBottomLeft: caret,
      caretHeight: caretHeight,
      screenSize: screenSize ?? screen,
      keyboardInset: keyboard,
      panelSize: panel ?? const Size(280, 300),
      minPanelHeight: minPanelHeight,
    );
  }

  group('dropdownPlacement', () {
    test('places the panel below the caret when there is room', () {
      final rect = place(const Offset(60, 300))!;
      expect(rect.left, 60);
      expect(rect.top, 308);
      expect(rect.size, const Size(280, 300));
    });

    test('flips above the caret when the panel would overflow the bottom',
        () {
      final rect = place(const Offset(60, 700))!;
      expect(rect.top, 700 - 16 - 8 - 300);
      expect(rect.size, const Size(280, 300));
    });

    test('caps the panel to the space below the caret when the full panel '
        'cannot fit either side', () {
      final rect = place(const Offset(60, 20), keyboard: 700)!;
      expect(rect.top, 28);
      expect(rect.size, const Size(280, 64));
      expect(rect.bottom, 92);
    });

    test('caps the panel to the space above the caret when only the space '
        'above is usable', () {
      final rect = place(const Offset(60, 250), keyboard: 500)!;
      expect(rect.top, 8);
      expect(rect.size, const Size(280, 218));
      expect(rect.bottom, 250 - 16 - 8);
    });

    test('caps the panel to the space below the caret when it cannot fit '
        'the full height', () {
      final rect = place(const Offset(60, 300), panel: const Size(280, 900))!;
      expect(rect.top, 308);
      expect(rect.size, const Size(280, 484));
      expect(rect.bottom, 792);
    });

    test('clamps horizontally at the right edge', () {
      final rect = place(const Offset(390, 300))!;
      expect(rect.left, 400 - 8 - 280);
      expect(rect.top, 308);
    });

    test('clamps horizontally at the left edge', () {
      final rect = place(const Offset(0, 300))!;
      expect(rect.left, 8);
    });

    test('narrows the panel when the screen is narrow', () {
      final rect = place(
        const Offset(60, 300),
        screenSize: const Size(200, 800),
      )!;
      expect(rect.size.width, 200 - 16);
    });

    test('respects the keyboard inset when deciding to flip', () {
      // Caret at 700: fits below without keyboard, flips with keyboard up to 400.
      final rect = place(const Offset(60, 700), keyboard: 400)!;
      expect(rect.top, lessThanOrEqualTo(700));
      expect(rect.bottom, lessThanOrEqualTo(800 - 400 - 8));
    });

    test('keeps the panel inside the visible area with the keyboard up', () {
      final rect = place(const Offset(60, 600), keyboard: 400)!;
      expect(rect.bottom, lessThanOrEqualTo(400 - 8));
      expect(rect.top, greaterThanOrEqualTo(8));
    });

    test('shrinks the panel when the visible area is very small', () {
      final rect = place(const Offset(60, 600), keyboard: 780)!;
      expect(rect.height, lessThanOrEqualTo(800 - 780 - 16));
      expect(rect.bottom, lessThanOrEqualTo(800 - 780 - 8));
      expect(rect.top, greaterThanOrEqualTo(8));
    });

    test('returns null when not even the minimum panel height fits', () {
      expect(place(const Offset(60, 40), keyboard: 720), isNull);
      expect(place(const Offset(60, 10), keyboard: 780), isNull);
    });

    test('never covers the caret line for any caret position', () {
      for (double dy = 20; dy <= 380; dy += 20) {
        final rect = place(Offset(60, dy), keyboard: 400);
        if (rect != null) {
          expect(
            rect.top >= dy + 8 || rect.bottom <= dy - 16 - 8,
            isTrue,
            reason: 'panel must not cover the caret line at dy=$dy',
          );
        }
      }
    });
  });
}

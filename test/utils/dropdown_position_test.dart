import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/dropdown_position.dart';

void main() {
  const screen = Size(400, 800);

  Rect place(Offset caret, {double caretHeight = 16, double keyboard = 0, Size? panel, Size? screenSize}) {
    return dropdownPlacement(
      caretBottomLeft: caret,
      caretHeight: caretHeight,
      screenSize: screenSize ?? screen,
      keyboardInset: keyboard,
      panelSize: panel ?? const Size(280, 300),
    );
  }

  group('dropdownPlacement', () {
    test('places the panel below the caret when there is room', () {
      final rect = place(const Offset(60, 300));
      expect(rect.left, 60);
      expect(rect.top, 308);
      expect(rect.size, const Size(280, 300));
    });

    test('flips above the caret when the panel would overflow the bottom',
        () {
      final rect = place(const Offset(60, 700));
      expect(rect.top, 700 - 16 - 8 - 300);
      expect(rect.size, const Size(280, 300));
    });

    test('clamps to the top edge when there is no room either way', () {
      final rect = place(const Offset(60, 20), keyboard: 700);
      expect(rect.top, 8);
      expect(rect.size, const Size(280, 84));
    });

    test('clamps horizontally at the right edge', () {
      final rect = place(const Offset(390, 300));
      expect(rect.left, 400 - 8 - 280);
      expect(rect.top, 308);
    });

    test('clamps horizontally at the left edge', () {
      final rect = place(const Offset(0, 300));
      expect(rect.left, 8);
    });

    test('narrows the panel when the screen is narrow', () {
      final rect = place(
        const Offset(60, 300),
        screenSize: const Size(200, 800),
      );
      expect(rect.size.width, 200 - 16);
    });

    test('respects the keyboard inset when deciding to flip', () {
      // Caret at 700: fits below without keyboard, flips with keyboard up to 400.
      final rect = place(const Offset(60, 700), keyboard: 400);
      expect(rect.top, lessThanOrEqualTo(700));
      expect(rect.bottom, lessThanOrEqualTo(800 - 400 - 8));
    });

    test('keeps the panel inside the visible area with the keyboard up', () {
      final rect = place(const Offset(60, 600), keyboard: 400);
      expect(rect.bottom, lessThanOrEqualTo(400 - 8));
      expect(rect.top, greaterThanOrEqualTo(8));
    });

    test('shrinks the panel when the visible area is very small', () {
      final rect = place(const Offset(60, 600), keyboard: 780);
      expect(rect.height, lessThanOrEqualTo(800 - 780 - 16));
      expect(rect.bottom, lessThanOrEqualTo(800 - 780 - 8));
      expect(rect.top, greaterThanOrEqualTo(8));
    });

    test('caps the panel height to the visible area', () {
      final rect = place(const Offset(60, 300), panel: const Size(280, 900));
      expect(rect.height, 800 - 16);
    });
  });
}

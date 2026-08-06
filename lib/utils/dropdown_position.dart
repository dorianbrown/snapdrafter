import 'dart:math' as math;
import 'dart:ui';

/// Computes where a dropdown panel should be placed so that it appears just
/// below [caretBottomLeft] (the global bottom-left of the text caret).
///
/// The panel is kept fully inside the visible area (the screen minus the
/// keyboard inset, with [margin] of breathing room) and never covers the
/// caret's text line: it is placed fully below the caret when possible, or
/// fully above it otherwise, shrinking to the available space on that side
/// when the full [panelSize] does not fit.
///
/// Returns null when not even [minPanelHeight] fits on either side without
/// covering the caret's text line, so the caller can hide the panel instead.
Rect? dropdownPlacement({
  required Offset caretBottomLeft,
  required double caretHeight,
  required Size screenSize,
  required double keyboardInset,
  required Size panelSize,
  double margin = 8,
  double minPanelHeight = 0,
}) {
  final double caretTop = caretBottomLeft.dy - caretHeight;
  final double visibleHeight = screenSize.height - keyboardInset;
  final double maxPanelWidth = math.max(0.0, screenSize.width - 2 * margin);
  final double panelWidth = panelSize.width.clamp(0.0, maxPanelWidth);

  // Available vertical space on each side of the caret's text line.
  final double spaceBelow =
      visibleHeight - margin - (caretBottomLeft.dy + margin);
  final double spaceAbove = caretTop - 2 * margin;

  double panelHeight;
  double top;
  if (panelSize.height <= spaceBelow) {
    // Full panel fits below the caret.
    panelHeight = panelSize.height;
    top = caretBottomLeft.dy + margin;
  } else if (panelSize.height <= spaceAbove) {
    // Full panel fits above the caret.
    panelHeight = panelSize.height;
    top = caretTop - margin - panelHeight;
  } else if (spaceBelow >= minPanelHeight) {
    // Shrunk panel below the caret.
    panelHeight = spaceBelow;
    top = caretBottomLeft.dy + margin;
  } else if (spaceAbove >= minPanelHeight) {
    // Shrunk panel above the caret.
    panelHeight = spaceAbove;
    top = caretTop - margin - panelHeight;
  } else {
    return null;
  }

  // Keep the panel inside the visible area. The caret always lies inside it
  // in realistic layouts, so this only constrains degenerate cases.
  final double maxPanelHeight = math.max(0.0, visibleHeight - 2 * margin);
  final double height = panelHeight.clamp(0.0, maxPanelHeight);
  final double maxTop = math.max(margin, visibleHeight - margin - height);
  top = top.clamp(margin, maxTop);

  // After clamping, the panel must still not cover the caret's text line.
  if (top < caretBottomLeft.dy + margin &&
      top + height > caretTop - margin) {
    return null;
  }

  final double left = caretBottomLeft.dx
      .clamp(margin, math.max(margin, screenSize.width - margin - panelWidth));
  return Rect.fromLTWH(left, top, panelWidth, height);
}

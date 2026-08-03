import 'dart:math' as math;
import 'dart:ui';

/// Computes where a dropdown panel should be placed so that it appears just
/// below [caretBottomLeft] (the global bottom-left of the text caret).
///
/// The panel is kept fully inside the visible area (the screen minus the
/// keyboard inset, with [margin] of breathing room) and flips above the caret
/// when there is not enough room below it.
Rect dropdownPlacement({
  required Offset caretBottomLeft,
  required double caretHeight,
  required Size screenSize,
  required double keyboardInset,
  required Size panelSize,
  double margin = 8,
}) {
  final double visibleHeight = screenSize.height - keyboardInset;
  final double maxPanelWidth = math.max(0.0, screenSize.width - 2 * margin);
  final double maxPanelHeight = math.max(0.0, visibleHeight - 2 * margin);
  final double panelWidth = panelSize.width.clamp(0.0, maxPanelWidth);
  final double panelHeight = panelSize.height.clamp(0.0, maxPanelHeight);

  final double left = caretBottomLeft.dx
      .clamp(margin, math.max(margin, screenSize.width - margin - panelWidth));

  final double belowCaret = caretBottomLeft.dy + margin;
  final double aboveCaret =
      caretBottomLeft.dy - caretHeight - margin - panelHeight;
  final bool fitsBelow = belowCaret + panelHeight <= visibleHeight - margin;
  final double maxTop =
      math.max(margin, visibleHeight - margin - panelHeight);
  final double top =
      (fitsBelow ? belowCaret : aboveCaret).clamp(margin, maxTop);

  return Rect.fromLTWH(left, top, panelWidth, panelHeight);
}

// Helpers for parsing and editing the multiline deck text format used by
// DeckTextEditor, where every card sits on its own line as "N Card Name".

/// Info about the card line containing [offset] in [text], if that line is a
/// card line in the form "N Card Name".
///
/// Returns null when the line is not a card line (e.g. "SIDEBOARD", empty
/// lines, or lines without a count prefix).
({int lineStart, int lineEnd, String countPrefix, String nameFragment})?
    cardLineAt(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  final lineStart = clamped == 0 ? 0 : text.lastIndexOf('\n', clamped - 1) + 1;
  final lineEnd = text.indexOf('\n', lineStart);
  final lineEndIndex = lineEnd == -1 ? text.length : lineEnd;
  final line = text.substring(lineStart, lineEndIndex);

  final match = RegExp(r'^(\d+)\s(.*)$').firstMatch(line);
  if (match == null) return null;

  return (
    lineStart: lineStart,
    lineEnd: lineEndIndex,
    countPrefix: '${match[1]} ',
    nameFragment: match[2] ?? '',
  );
}

/// Replaces only the card-name portion of the line containing [offset] in
/// [text] with [newName], leaving every other line untouched. Returns [text]
/// unchanged when the offset is not on a card line.
String replaceCardNameInLine(String text, int offset, String newName) {
  final info = cardLineAt(text, offset);
  if (info == null) return text;
  return text.replaceRange(
      info.lineStart + info.countPrefix.length, info.lineEnd, newName);
}

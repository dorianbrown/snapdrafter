/// Case-insensitive search over a preloaded list of full card names
/// (e.g. "Fire // Ice"). Prefix matches come first, then substring matches,
/// capped at [maxResults].
///
/// Matching against full names means a dual-faced card is found by any of
/// its faces ("ice"), its full name ("fire // ice"), or a prefix ("fire").
List<String> searchCardNames(
  List<String> names,
  String query, {
  int maxResults = 8,
}) {
  final lower = query.trim().toLowerCase();
  if (lower.isEmpty) return const [];

  final prefixMatches = <String>[];
  final substringMatches = <String>[];
  for (final name in names) {
    if (prefixMatches.length >= maxResults &&
        substringMatches.length >= maxResults) {
      break;
    }
    final lowerName = name.toLowerCase();
    if (lowerName.startsWith(lower)) {
      prefixMatches.add(name);
    } else if (substringMatches.length < maxResults &&
        lowerName.contains(lower)) {
      substringMatches.add(name);
    }
  }
  return [...prefixMatches, ...substringMatches].take(maxResults).toList();
}

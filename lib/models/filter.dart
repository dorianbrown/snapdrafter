import 'package:snapdrafter/data/models/deck.dart';

class Filter {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? setId;
  final String? cubecobraId;
  final int minWins;
  final int maxWins;
  final List<String> tags;
  final List<String> includedColors;
  final List<String> excludedColors;

  const Filter({
    this.startDate,
    this.endDate,
    this.setId,
    this.cubecobraId,
    required this.minWins,
    required this.maxWins,
    this.tags = const [],
    this.includedColors = const [],
    this.excludedColors = const [],
  });

  Filter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? setId,
    String? cubecobraId,
    int? minWins,
    int? maxWins,
    List<String>? tags,
    List<String>? includedColors,
    List<String>? excludedColors,
  }) {
    return Filter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      setId: setId ?? this.setId,
      cubecobraId: cubecobraId ?? this.cubecobraId,
      minWins: minWins ?? this.minWins,
      maxWins: maxWins ?? this.maxWins,
      tags: tags ?? this.tags,
      includedColors: includedColors ?? this.includedColors,
      excludedColors: excludedColors ?? this.excludedColors,
    );
  }

  Filter clearSetId() {
    return Filter(
      startDate: startDate,
      endDate: endDate,
      setId: null,
      cubecobraId: cubecobraId,
      minWins: minWins,
      maxWins: maxWins,
      tags: tags,
      includedColors: includedColors,
      excludedColors: excludedColors,
    );
  }

  Filter clearCubecobraId() {
    return Filter(
      startDate: startDate,
      endDate: endDate,
      setId: setId,
      cubecobraId: null,
      minWins: minWins,
      maxWins: maxWins,
      tags: tags,
      includedColors: includedColors,
      excludedColors: excludedColors,
    );
  }

  Filter clearDateRange() {
    return Filter(
      startDate: null,
      endDate: null,
      setId: setId,
      cubecobraId: cubecobraId,
      minWins: minWins,
      maxWins: maxWins,
      tags: tags,
      includedColors: includedColors,
      excludedColors: excludedColors,
    );
  }

  Filter clearWinRange() {
    return Filter(
      startDate: startDate,
      endDate: endDate,
      setId: setId,
      cubecobraId: cubecobraId,
      minWins: 0,
      maxWins: 3,
      tags: tags,
      includedColors: includedColors,
      excludedColors: excludedColors,
    );
  }

  Filter clearTags() {
    return Filter(
      startDate: startDate,
      endDate: endDate,
      setId: setId,
      cubecobraId: cubecobraId,
      minWins: minWins,
      maxWins: maxWins,
      tags: const [],
      includedColors: includedColors,
      excludedColors: excludedColors,
    );
  }

  Filter clearColors() {
    return Filter(
      startDate: startDate,
      endDate: endDate,
      setId: setId,
      cubecobraId: cubecobraId,
      minWins: minWins,
      maxWins: maxWins,
      tags: tags,
      includedColors: const [],
      excludedColors: const [],
    );
  }

  bool isEmpty() {
    return setId == null &&
        cubecobraId == null &&
        startDate == null &&
        endDate == null &&
        minWins == 0 &&
        maxWins == 3 &&
        tags.isEmpty &&
        includedColors.isEmpty &&
        excludedColors.isEmpty;
  }

  bool matchesDeck(Deck deck) {
    final date = DateTime.parse(deck.ymd);
    if (startDate != null && date.isBefore(startDate!)) return false;
    if (endDate != null && date.isAfter(endDate!)) return false;
    if (setId != null && deck.setId != setId) return false;
    if (cubecobraId != null && deck.cubecobraId != cubecobraId) return false;

    // Check if all included colors are present in the deck's colors
    if (includedColors.isNotEmpty) {
      for (final color in includedColors) {
        if (!deck.colors.contains(color)) {
          return false;
        }
      }
    }
    
    // Check if any excluded colors are present in the deck's colors
    if (excludedColors.isNotEmpty) {
      for (final color in excludedColors) {
        if (deck.colors.contains(color)) {
          return false;
        }
      }
    }

    // Check if all tags in the filter are present in the deck's tags
    if (tags.isNotEmpty) {
      for (final tag in tags) {
        if (!deck.tags.contains(tag)) return false;
      }
    }

    final wins = deck.wins;
    if (wins == null) {
      // If we're filtering for non-zero wins but deck has no win data, exclude it
      if (minWins > 0 || maxWins < 3) return false;
    } else {
      if (wins < minWins) return false;
      if (wins > maxWins) return false;
    }

    return true;
  }
}

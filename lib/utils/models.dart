import 'package:collection/collection.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:snapdrafter/data/models/deck.dart';

const List<String> typeOrder = [
  "Creature",
  "Planeswalker",
  "Instant",
  "Sorcery",
  "Artifact",
  "Enchantment",
  "Battle",
  "Land",
];

const List<String> colorOrder = [
  "White",
  "Blue",
  "Black",
  "Red",
  "Green",
  "Multicolor",
  "Colorless"
];

class Filter {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? setId;
  final String? cubecobraId;
  final int minWins;
  final int maxWins;

  const Filter({
    this.startDate,
    this.endDate,
    this.setId,
    this.cubecobraId,
    required this.minWins,
    required this.maxWins,
  });

  Filter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? setId,
    String? cubecobraId,
    int? minWins,
    int? maxWins,
  }) {
    return Filter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      setId: setId ?? this.setId,
      cubecobraId: cubecobraId ?? this.cubecobraId,
      minWins: minWins ?? this.minWins,
      maxWins: maxWins ?? this.maxWins,
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
    );
  }

  bool isEmpty() {
    return setId == null && 
           cubecobraId == null &&
           startDate == null && 
           endDate == null &&
           minWins == 0 &&
           maxWins == 3;
  }

  bool matchesDeck(Deck deck) {
    final date = DateTime.parse(deck.ymd);
    if (startDate != null && date.isBefore(startDate!)) return false;
    if (endDate != null && date.isAfter(endDate!)) return false;
    if (setId != null && deck.setId != setId) return false;
    if (cubecobraId != null && deck.cubecobraId != cubecobraId) return false;
    
    if (deck.winLoss == null) {
      // If we're filtering for non-zero wins but deck has no win data, exclude it
      if (minWins > 0 || maxWins < 3) return false;
    } else {
      final parts = deck.winLoss!.split('/');
      final wins = int.tryParse(parts[0]);
      
      if (wins != null) {
        if (wins < minWins) return false;
        if (wins > maxWins) return false;
      }
    }
    
    return true;
  }
}

class DeckChangeNotifier extends ChangeNotifier {
  static final DeckChangeNotifier _instance = DeckChangeNotifier._internal();
  
  factory DeckChangeNotifier() => _instance;
  
  DeckChangeNotifier._internal();

  bool _needsRefresh = false;

  bool get needsRefresh => _needsRefresh;

  void markNeedsRefresh() {
    _needsRefresh = true;
    notifyListeners();
  }

  void clearRefresh() {
    _needsRefresh = false;
  }
}

class Detection {
  Card? card;
  final String ocrText;
  final int? ocrDistance;
  final img.Image? textImage;

  Detection({
    required this.card,
    required this.ocrText,
    this.ocrDistance,
    this.textImage
  });
}

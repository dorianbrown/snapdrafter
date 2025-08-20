import 'package:flutter/material.dart' hide Card;

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
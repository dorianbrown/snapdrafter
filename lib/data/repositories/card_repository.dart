import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '/data/database/database_helper.dart';
import '/data/models/card.dart';

class CardRepository {
  late final DatabaseHelper _dbHelper;
  List<Card> _allCards = [];
  bool _cardsLoaded = false;
  bool _dbHelperLoaded = false;

  // Make class singleton
  CardRepository._privateConstructor();
  static final CardRepository _instance = CardRepository._privateConstructor();
  factory CardRepository() {
    if (!_instance._dbHelperLoaded) {
      _instance.init();
    }
    return _instance;
  }

  void init() {
    _dbHelper = DatabaseHelper();
    _dbHelperLoaded = true;
  }

  Future<Database> get _db async => await _dbHelper.database;

  Future<void> populateCardsTable(List<Card> cards, Map<String, dynamic> scryfallMetadata) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      var batch = txn.batch();
      batch.insert(
        "scryfall_metadata",
        scryfallMetadata,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.delete('cards'); // Removes all rows from table.
      for (final card in cards) {
        batch.insert(
          'cards',
          card.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit();
    });
    _cardsLoaded = false; // Invalidate cache
  }

  Future<List<Card>> getAllCards() async {
    if (!_cardsLoaded || _allCards.isEmpty) {
      final dbClient = await _db;
      final result = await dbClient.query('cards');
      _allCards = result.map((map) => Card.fromMap(map)).toList();
      if (_allCards.isNotEmpty) {
        _cardsLoaded = true;
      }
    }
    return _allCards;
  }

  // Add methods for cards_to_tokens and tokens tables if needed
}

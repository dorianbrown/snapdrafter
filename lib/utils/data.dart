import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class DeckStorage {
  late Database _database;
  late List<Card> _allCards;
  Map<String,Card>? _allCardsMap;
  var cardsLoaded = false;
  final String _databaseName = 'decklistScanner.db';
  final int _databaseVersion = 1;

  DeckStorage._privateConstructor();
  static final DeckStorage _instance = DeckStorage._privateConstructor();
  factory DeckStorage() {
    return _instance;
  }

  Future<void> init() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), _databaseName),
      version: _databaseVersion,
      onCreate: (db, version) {
        db.execute(
            """
          CREATE TABLE cards(
            scryfall_id TEXT PRIMARY KEY,
            oracle_id TEXT NOT NULL,
            name TEXT NOT NULL,
            title TEXT NOT NULL,
            type TEXT NOT NULL,
            image_uri TEXT,
            colors TEXT,
            mana_cost TEXT,
            mana_value INTEGER NOT NULL)
          """
        );
        db.execute(
          """
          CREATE TABLE decks(
            id INTEGER PRIMARY KEY, 
            name TEXT NOT NULL, 
            datetime TEXT NOT NULL)
          """
        );
        db.execute(
          """
          CREATE TABLE decklists(
            id INTEGER PRIMARY KEY, 
            deck_id INTEGER NOT NULL, 
            scryfall_id TEXT NOT NULL)
          """
        );
        db.execute(
          """
          CREATE TABLE scryfall_metadata(
            id INTEGER PRIMARY KEY,
            datetime TEXT NOT NULL,
            newest_set_name TEXT NOT NULL
          )
          """
        );
        debugPrint("sqflite tables created");
      },
    );

    // Print row counts of all tables
    for (String tableName in ['cards', 'decks', 'decklists']) {
      final int? rowCount = await countRows(tableName);
      debugPrint("$tableName: $rowCount");
    }
  }

  Future<void> populateCardsTable(List<Card> cards, Map<String, dynamic> scryfallMetadata) async {

    _database.transaction((txn) async {
      var batch = txn.batch();
      batch.insert(
          "scryfall_metadata",
          scryfallMetadata,
          conflictAlgorithm: ConflictAlgorithm.replace
      );
      batch.delete('cards');  // Removes all rows from table.
      for (final card in cards) {
        batch.insert(
          'cards',
          card.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore
        );
      }
      await batch.commit();
    });
  }

  Future<Map<String, Card>> getCardsMap() async {
    if (_allCardsMap == null) {
      final allCards = await getAllCards();
      _allCardsMap = {
        for (final card in allCards) card.scryfallId: card
      };
    }
    return _allCardsMap!;
  }

  Future<List<Card>> getAllCards() async {
    if (!cardsLoaded) {
      final result = await _database.query('cards');
      _allCards = [
        for (final {
        "scryfall_id": scryfallId as String,
        "oracle_id": oracleId as String,
        "name": name as String,
        "title": title as String,
        "type": type as String,
        "image_uri": imageUri as String,
        "colors": colors as String,
        "mana_cost": manaCost as String,
        "mana_value": manaValue
        } in result)
          Card(
              scryfallId: scryfallId,
              oracleId: oracleId,
              name: name,
              title: title,
              type: type,
              imageUri: imageUri,
              colors: colors,
              manaCost: manaCost,
              manaValue: manaValue as int
          )
      ];
      if (_allCards.isNotEmpty) {
        cardsLoaded = true;
      }
    }
    return _allCards;
  }

  Future<int> insertDeck(Map<String, Object?> map) async {
    return await _database.insert(
      'decks',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>> getScryfallMetadata() async {
    final result = await _database.query("scryfall_metadata");
    for (final res in result) {
      return res;
    }
    return {};
  }

  Future<List<Deck>> getAllDecks() async {
    final decks = await _database.query('decks');
    final decklists = await _database.query('decklists');
    final cardsMap = await getCardsMap();

    final List<Deck> deckList = [];
    for (final deck in decks) {
      final deckId = deck['id'] as int;
      final deckName = deck['name'] as String;
      final deckDateTime = DateTime.parse(deck['datetime'] as String);

      var currentDecklist = decklists
          .where((x) => x['deck_id'] == deckId)
          .map((x) => cardsMap[x["scryfall_id"]]!)
          .toList();

      deckList.add(Deck(
        id: deckId,
        name: deckName,
        dateTime: deckDateTime,
        cards: currentDecklist
      ));
    }
    return deckList;
  }

  Future<void> deleteDeck(int id) async {
    await _database.delete(
      'decks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int?> countRows(String tableName) async {
    final result = await _database.rawQuery(
        "SELECT COUNT(*) FROM $tableName"
    );
    return Sqflite.firstIntValue(result);
  }

  Future<int> saveDeck(String name, DateTime dateTime, List<Card> cards) async {

    int deckId = await insertDeck({'name': name, 'dateTime': dateTime.toIso8601String()});
    _database.transaction((txn) async {
      var batch = txn.batch();
      for (final card in cards) {
        batch.insert(
            'decklists',
            Decklist(deckId: deckId, scryfallId: card.scryfallId).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      await batch.commit();
    });
    debugPrint("Deck insert successfully, deck_id: $deckId");
    return deckId;
  }
}
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'utils.dart';
import 'models.dart';

class DeckStorage {
  late Database _database;
  late List<Card> _allCards;
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
            win_loss TEXT,
            set_id TEXT,
            cube_id int,
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
        db.execute(
          """
          CREATE TABLE sets(
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            released_at TEXT NOT NULL
          )
          """
        );
        debugPrint("sqflite tables created");
      },
    );
  }

  Future<void> populateSetsTable() async {
    final response = await get(Uri.parse('http://api.scryfall.com/sets'));

    if (response.statusCode == 200) {
      final values = json.decode(response.body);
      String ymdString = convertDatetimeToYMD(DateTime.now(), sep: "-");
      final setsData = values['data']
          .where((x) => (
            // keep draftable sets
            ["expansion", "core" ,"masters"].contains(x["set_type"])) &
            (ymdString.compareTo(x["released_at"]) > 0) &
            // discard digital sets
            !x["digital"]
          )
          .map((x) => {"code": x["code"], "name": x["name"], "released_at": x["released_at"]})
          .toList();

      _database.transaction((txn) async {
        var batch = txn.batch();
        for (final set in setsData) {
          batch.insert(
              "sets",
              set,
              conflictAlgorithm: ConflictAlgorithm.replace
          );
        }
        await batch.commit();
      });
      debugPrint("Added ${setsData.length} sets to sets table");
    } else {
      throw Exception('Failed to load sets');
    }
  }

  Future<List<Set>> getAllSets() async {
    final result = await _database.query('sets');
     return [
      for (final {
      "code": code as String,
      "name": name as String,
      "released_at": releasedAt as String,
      } in result)
        Set(
          code: code,
          name: name,
          releasedAt: releasedAt
        )
    ];
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
    return {};
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
    final cards = await _database.rawQuery(
      """
      SELECT decklists.deck_id, cards.*
      FROM decklists 
      INNER JOIN cards ON decklists.scryfall_id = cards.scryfall_id 
      """
    );

    final List<Deck> deckList = [];
    for (final deck in decks) {
      final deckId = deck['id'] as int;
      final winLoss = deck['win_loss'] as String?;
      final setId = deck['set_id'] as String?;
      final cubeId = deck['cube_id'] as int?;
      final deckDateTime = DateTime.parse(deck['datetime'] as String);

      var currentDecklist = cards
          .where((x) => x['deck_id'] == deckId)
          .map((x) => Card.fromMap(x))
          .toList();

      deckList.add(Deck(
        id: deckId,
        winLoss: winLoss,
        setId: setId,
        cubeId: cubeId,
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
    await _database.delete(
      'decklists',
      where: 'deck_id = ?',
      whereArgs: [id],
    );
  }

  Future<int?> countRows(String tableName) async {
    final result = await _database.rawQuery(
        "SELECT COUNT(*) FROM $tableName"
    );
    return Sqflite.firstIntValue(result);
  }

  Future<void> updateDecklist(int deckId, List<Card> cards) async {
    _database.transaction((txn) async {
      var batch = txn.batch();
      batch.delete('decklists', where: 'deck_id = ?', whereArgs: [deckId]);
      for (final card in cards) {
        batch.insert(
            'decklists',
            Decklist(deckId: deckId, scryfallId: card.scryfallId).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      await batch.commit();
    });
  }

  Future<int> saveNewDeck(DateTime dateTime, List<Card> cards) async {
    int deckId = await insertDeck({'dateTime': dateTime.toIso8601String()});
    updateDecklist(deckId, cards);
    debugPrint("Deck insert successfully, deck_id: $deckId");
    return deckId;
  }
}
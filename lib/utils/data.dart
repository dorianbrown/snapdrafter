import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class DeckStorage {
  late Database _database;
  late List<Card> _allCards;
  var cardsLoaded = false;
  final String _databaseName = 'decklistScanner.db';
  final int _databaseVersion = 1;

  Future<void> init() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), _databaseName),
      version: _databaseVersion,
      onCreate: (db, version) {
        db.execute(
            """
          CREATE TABLE cards(
            id INTEGER PRIMARY KEY,
            name TEXT,
            title TEXT,
            type TEXT,
            imageUri TEXT,
            colors TEXT,
            manaValue TEXT)
          """
        );
        db.execute(
          """
          CREATE TABLE decks(
            id INTEGER PRIMARY KEY, 
            name TEXT, 
            datetime TEXT)
          """
        );
        db.execute(
          """
          CREATE TABLE decklists(
            id INTEGER PRIMARY KEY, 
            deckId INTEGER, 
            cardId INTEGER)
          """
        );
        debugPrint("sqflite tables created");
      },
    );

    // Populate cards table if it is empty
    if (await countRows("cards") == 0) {
      debugPrint("Populating cards table");
      populateCardsTable().then((val) async {
        final int? cardCount = await countRows("cards");
        debugPrint("Cards in db: $cardCount");
      });
    }

    // Print row counts of all tables
    for (String tableName in ['cards', 'decks', 'decklists']) {
      final int? rowCount = await countRows(tableName);
      debugPrint("$tableName: $rowCount");
    }
  }

  Future<void> populateCardsTable() async {
    final String cardJsonString = await rootBundle.loadString("assets/card_data.json");
    final cardsMap = jsonDecode(cardJsonString);

    _database.transaction((txn) async {
      var batch = txn.batch();
      for (final cardMap in cardsMap) {

        final input_map = {
          'name': cardMap['name'],
          'title': cardMap['name'].split(" // ")[0],
          'type': cardMap['type'],
          'imageUri': cardMap['image'],
          'colors': cardMap['colors'].join(""),
          'manaValue': cardMap['cmc'].toInt()
        };

        batch.insert(
          'cards',
          input_map,
          conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      await batch.commit();
    });
  }

  Future<List<Card>> getAllCards() async {
    if (!cardsLoaded) {
      final result = await _database.query('cards');
      _allCards = [
        for (final {
        "id": id as int,
        "name": name as String,
        "title": title as String,
        "type": type as String,
        "imageUri": imageUri as String,
        "colors": colors as String,
        "manaValue": manaValue as String
        } in result)
          Card(
              id: id,
              name: name,
              title: title,
              type: type,
              imageUri: imageUri,
              colors: colors,
              manaValue: int.parse(manaValue)
          )
      ];
      cardsLoaded = true;
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

  Future<List<Deck>> getAllDecks() async {
    final decks = await _database.query('decks');
    final decklists = await _database.query('decklists');
    final cards = await getAllCards();

    final List<Deck> deckList = [];
    for (final deck in decks) {
      final deckId = deck['id'] as int;
      final deckName = deck['name'] as String;
      final deckDateTime = DateTime.parse(deck['datetime'] as String);

      // FIXME: Mismatch of card id's, either here or at writing to db.
      var currentDecklist = decklists
          .where((x) => x['deckId'] == deckId)
          .map((x) => cards[int.parse(x['cardId'].toString()) - 1])
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
            Decklist(deckId: deckId, cardId: card.id).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      await batch.commit();
    });
    debugPrint("Deck insert successfully, deckId: $deckId");
    return deckId;
  }
}
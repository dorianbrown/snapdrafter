import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/deck.dart';
import '../models/card.dart';
import '../models/decklist.dart';

class DecklistStorage {
  late Database _database;

  void init() async {
    final _database = openDatabase(
      join(await getDatabasesPath(), 'decklistScanner.db'),
      version: 1,
      onCreate: (db, version) {
        db.execute(
            """
          CREATE TABLE cards(
            id INTEGER PRIMARY KEY,
            scryfallId TEXT,
            name TEXT,
            flavorName TEXT,
            type TEXT,
            imageUri TEXT,
            color TEXT,
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
  }

  Future<void> insertDeck(Deck deck) async {
    await _database.insert(
      'decks',
      deck.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Deck>> getAllDecks() async {
    final decks = await _database.query('decks');
    return [
      for (final {
        'id': id as int,
        'name': name as String,
        'datetime': datetime as String,
        'decklistId': decklistId as int
      } in decks)
        Deck(id: id, name: name, dateTime: DateTime.parse(datetime), decklistId: decklistId)
    ];
  }
}
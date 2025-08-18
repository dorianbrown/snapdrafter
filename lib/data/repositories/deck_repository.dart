import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../models/decklist.dart';

// Placeholder for the utility function, ensure it's accessible
String convertDatetimeToYMD(DateTime dateTime, {String sep = ""}) {
  // Implement or import this utility function
  return "${dateTime.year}$sep${dateTime.month.toString().padLeft(2, '0')}$sep${dateTime.day.toString().padLeft(2, '0')}";
}

class DeckRepository {
  final DatabaseHelper _dbHelper;

  DeckRepository(this._dbHelper);

  Future<Database> get _db async => await _dbHelper.database;

  Future<int> insertDeck(Map<String, Object?> map) async {
    final dbClient = await _db;
    return await dbClient.insert(
      'decks',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Deck>> getAllDecks() async {
    final dbClient = await _db;
    final decksData = await dbClient.query('decks');
    final cardsData = await dbClient.rawQuery("""
      SELECT decklists.deck_id, cards.*
      FROM decklists 
      INNER JOIN cards ON decklists.scryfall_id = cards.scryfall_id 
    """);

    final List<Deck> deckList = [];
    for (final deck in decksData) {
      final deckId = deck['id'] as int;
      final name = deck['name'] as String?;
      final winLoss = deck['win_loss'] as String?;
      final setId = deck['set_id'] as String?;
      final cubecobraId = deck['cubecobra_id'] as String?;
      final ymd = deck['ymd'] as String;

      var currentDecklist = cardsData
          .where((x) => x['deck_id'] == deckId)
          .map((x) => Card.fromMap(x))
          .toList();

      deckList.add(Deck(
          id: deckId,
          name: name,
          winLoss: winLoss,
          setId: setId,
          cubecobraId: cubecobraId,
          ymd: ymd,
          cards: currentDecklist
      ));
    }
    return deckList;
  }

  Future<void> deleteDeck(int id) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      await txn.delete(
        'decks',
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'decklists',
        where: 'deck_id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> updateDecklist(int deckId, List<Card> cards) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      var batch = txn.batch();
      batch.delete('decklists', where: 'deck_id = ?', whereArgs: [deckId]);
      for (final card in cards) {
        batch.insert(
          'decklists',
          Decklist(deckId: deckId, scryfallId: card.scryfallId).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit();
    });
  }

  Future<int> saveNewDeck(DateTime dateTime, List<Card> cards) async {
    String ymd = convertDatetimeToYMD(dateTime);
    int deckId = await insertDeck({'ymd': ymd}); // Get the auto-generated ID for new deck from database
    await updateDecklist(deckId, cards);
    debugPrint("Deck inserted successfully, deck_id: $deckId");
    return deckId;
  }

}

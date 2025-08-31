import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../models/decklist.dart';

import '/utils/utils.dart';

class DeckRepository {
  late final DatabaseHelper _dbHelper;
  bool _dbHelperLoaded = false;

  DeckRepository._privateConstructor();
  static final DeckRepository _instance = DeckRepository._privateConstructor();
  factory DeckRepository() {
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
    
    // Get tags for all decks
    final tagsData = await dbClient.rawQuery("""
      SELECT dt.deck_id, t.name 
      FROM deck_tags dt 
      INNER JOIN tags t ON dt.tag_id = t.id
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
          
      // Get tags for this deck
      var deckTags = tagsData
          .where((x) => x['deck_id'] == deckId)
          .map((x) => x['name'] as String)
          .toList();

      deckList.add(Deck(
          id: deckId,
          name: name,
          winLoss: winLoss,
          setId: setId,
          cubecobraId: cubecobraId,
          ymd: ymd,
          imagePath: imagePath,
          cards: currentDecklist,
          tags: deckTags
      ));
    }
    return deckList;
  }

  Future<void> deleteDeck(int id) async {
    final dbClient = await _db;
    
    // Get image path before deletion
    final deck = await dbClient.query(
      'decks',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    final imagePath = deck.isNotEmpty ? deck.first['image_path'] as String? : null;
    
    await dbClient.transaction((txn) async {
      // Delete image file if exists
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      await txn.delete('decks', where: 'id = ?', whereArgs: [id]);
      await txn.delete('decklists', where: 'deck_id = ?', whereArgs: [id]);
      await txn.delete('deck_tags', where: 'deck_id = ?', whereArgs: [id]);
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

  Future<String?> _saveDeckImage(Uint8List imageBytes, int deckId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = '${directory.path}/deck_$deckId_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final file = File(imagePath);
      await file.writeAsBytes(imageBytes);
      
      return imagePath;
    } catch (e) {
      debugPrint('Error saving deck image: $e');
      return null;
    }
  }

  Future<void> _updateDeckImagePath(int deckId, String imagePath) async {
    final dbClient = await _db;
    await dbClient.update(
      'decks',
      {'image_path': imagePath},
      where: 'id = ?',
      whereArgs: [deckId],
    );
  }

  Future<int> saveNewDeck(DateTime dateTime, List<Card> cards, {Uint8List? imageBytes}) async {
    String ymd = convertDatetimeToYMD(dateTime);
    int deckId = await insertDeck({'ymd': ymd});
    
    // Save image if provided
    if (imageBytes != null) {
      final imagePath = await _saveDeckImage(imageBytes, deckId);
      if (imagePath != null) {
        await _updateDeckImagePath(deckId, imagePath);
      }
    }
    
    await updateDecklist(deckId, cards);
    debugPrint("Deck inserted successfully, deck_id: $deckId");
    return deckId;
  }

  // Tag management methods
  Future<List<String>> getAllTags() async {
    final dbClient = await _db;
    final result = await dbClient.query('tags');
    return result.map((row) => row['name'] as String).toList();
  }

  Future<void> addTagToDeck(int deckId, String tagName) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      // Insert tag if it doesn't exist
      var tagResult = await txn.rawQuery(
        'SELECT id FROM tags WHERE name = ?',
        [tagName]
      );
      int tagId;
      if (tagResult.isEmpty) {
        tagId = await txn.insert('tags', {'name': tagName});
      } else {
        tagId = tagResult.first['id'] as int;
      }
      
      // Link tag to deck
      await txn.insert(
        'deck_tags',
        {'deck_id': deckId, 'tag_id': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<void> removeTagFromDeck(int deckId, String tagName) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      // First remove the tag from the deck
      await txn.rawDelete('''
        DELETE FROM deck_tags 
        WHERE deck_id = ? AND tag_id IN (
          SELECT id FROM tags WHERE name = ?
        )
      ''', [deckId, tagName]);

      // Then remove any dangling tags (tags with no associated decks)
      await txn.rawDelete('''
        DELETE FROM tags 
        WHERE id NOT IN (
          SELECT DISTINCT tag_id FROM deck_tags
        )
      ''');
    });
  }

}

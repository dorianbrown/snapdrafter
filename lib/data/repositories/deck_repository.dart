import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../models/deck_upsert.dart';

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

  Future<void> _replaceDeckCardList(
    Transaction txn,
    String tableName,
    int deckId,
    List<Card> cards,
  ) async {
    final batch = txn.batch();
    batch.delete(tableName, where: 'deck_id = ?', whereArgs: [deckId]);
    for (final card in cards) {
      batch.insert(
        tableName,
        {'deck_id': deckId, 'scryfall_id': card.scryfallId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Updates a deck's metadata and/or lists.
  ///
  /// This is the single entry point for updating:
  /// - the `decks` row (metadata)
  /// - mainboard (`decklists`)
  /// - sideboard (`sideboard_lists`)
  Future<void> updateDeck(DeckUpsert deck) async {
    if (deck.id == null) {
      throw ArgumentError('DeckUpsert.id must be set for updateDeck()');
    }

    final deckId = deck.id!;
    final dbClient = await _db;

    await dbClient.transaction((txn) async {
      final Map<String, Object?> updates = {
        'name': deck.name,
        'win_loss': deck.winLoss,
        'set_id': deck.setId,
        'cubecobra_id': deck.cubecobraId,
        'ymd': deck.ymd,
      };

      // Remove null values to avoid overwriting with null
      updates.removeWhere((key, value) => value == null);

      if (updates.isNotEmpty) {
        await txn.update(
          'decks',
          updates,
          where: 'id = ?',
          whereArgs: [deckId],
        );
      }

      await _replaceDeckCardList(txn, 'decklists', deckId, deck.cards);
      await _replaceDeckCardList(txn, 'sideboard_lists', deckId, deck.sideboard);
    });
  }

  Future<List<Deck>> getAllDecks() async {
    final dbClient = await _db;
    final decksData = await dbClient.query('decks');
    final cardsData = await dbClient.rawQuery("""
      SELECT decklists.deck_id, cards.*
      FROM decklists 
      INNER JOIN cards 
      ON decklists.scryfall_id = cards.scryfall_id 
    """);

    final sideboardCardsData = await dbClient.rawQuery("""
      SELECT sideboard_lists.deck_id, cards.*
      FROM sideboard_lists
      INNER JOIN cards 
      ON sideboard_lists.scryfall_id = cards.scryfall_id 
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
      String? imagePath = deck['image_path'] as String?;

      final currentDecklist = cardsData
          .where((x) => x['deck_id'] == deckId)
          .map((x) => Card.fromMap(x))
          .toList();

      final sideboardCardlist = sideboardCardsData
          .where((x) => x['deck_id'] == deckId)
          .map((x) => Card.fromMap(x))
          .toList();
          
      // Get tags for this deck
      final deckTags = tagsData
          .where((x) => x['deck_id'] == deckId)
          .map((x) => x['name'] as String)
          .toList();

      // Transform image_path from partial to full path
      final directory = await getApplicationDocumentsDirectory();
      if (imagePath != null) {
        final file = File('${directory.path}/$imagePath');
        if (await file.exists()) {
          imagePath = file.path;
        }
      }

      deckList.add(Deck(
          id: deckId,
          name: name,
          winLoss: winLoss,
          setId: setId,
          cubecobraId: cubecobraId,
          ymd: ymd,
          imagePath: imagePath,
          cards: currentDecklist,
          sideboard: sideboardCardlist,
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
      await txn.delete('decks', where: 'id = ?', whereArgs: [id]);
      await txn.delete('decklists', where: 'deck_id = ?', whereArgs: [id]);
      await txn.delete('sideboard_lists', where: 'deck_id = ?', whereArgs: [id]);
      await txn.delete('deck_tags', where: 'deck_id = ?', whereArgs: [id]);

      // Delete image file if exists
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    });
  }

  /// Creates a new deck and returns the persisted `Deck` (with a real id).
  ///
  /// This is the single entry point for creating:
  /// - the `decks` row (metadata)
  /// - mainboard (`decklists`)
  /// - sideboard (`sideboard_lists`)
  Future<Deck> saveNewDeck(DeckUpsert deck, {Image? image}) async {
    final dbClient = await _db;

    final String ymd = deck.ymd ?? convertDatetimeToYMD(DateTime.now());
    final String? storedImagePath = image != null ? await _saveDeckImage(image) : null;

    late final int deckId;
    await dbClient.transaction((txn) async {
      deckId = await txn.insert(
        'decks',
        {
          'name': deck.name,
          'win_loss': deck.winLoss,
          'set_id': deck.setId,
          'cubecobra_id': deck.cubecobraId,
          'ymd': ymd,
          'image_path': storedImagePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await _replaceDeckCardList(txn, 'decklists', deckId, deck.cards);
      await _replaceDeckCardList(txn, 'sideboard_lists', deckId, deck.sideboard);
    });

    // Match the "loaded deck" shape: imagePath should be a full path if it exists.
    String? fullImagePath;
    if (storedImagePath != null) {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$storedImagePath');
      if (await file.exists()) {
        fullImagePath = file.path;
      }
    }

    return Deck(
      id: deckId,
      name: deck.name,
      winLoss: deck.winLoss,
      setId: deck.setId,
      cubecobraId: deck.cubecobraId,
      ymd: ymd,
      imagePath: fullImagePath,
      cards: deck.cards,
      sideboard: deck.sideboard,
      tags: const [],
    );
  }

  Future<String?> _saveDeckImage(Image image) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // Create folder if it doesn't exist
      Directory('${directory.path}/deck_images').createSync(recursive: true);
      final imagePath = 'deck_images/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final file = File("${directory.path}/$imagePath");
      await file.writeAsBytes(encodeJpg(image, quality: 60));

      return imagePath;
    } catch (e) {
      debugPrint('Error saving deck image: $e');
      return null;
    }
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

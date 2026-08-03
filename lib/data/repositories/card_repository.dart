import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '/data/database/database_helper.dart';
import '/data/models/card.dart';

class CardRepository {
  late final DatabaseHelper _dbHelper;
  bool _dbHelperLoaded = false;

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

  Future<bool> isCardTableEmpty() async {
    final dbClient = await _db;
    final result = await dbClient.rawQuery('SELECT COUNT(*) as count FROM cards');
    return (result.first['count'] as int) == 0;
  }

  Future<void> populateCardsTable(List<Card> cards, Map<String, dynamic> scryfallMetadata) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      var batch = txn.batch();
      batch.insert(
        "scryfall_metadata",
        scryfallMetadata,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.delete('cards');
      for (final card in cards) {
        batch.insert(
          'cards',
          card.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit();
    });
  }

  Future<List<Card>> getAllCards() async {
    final dbClient = await _db;
    final result = await dbClient.query('cards');
    return result.map((map) => Card.fromMap(map)).toList();
  }

  Future<List<Card>> getCardsByScryfallIds(List<String> scryfallIds) async {
    if (scryfallIds.isEmpty) return [];
    final dbClient = await _db;
    final placeholders = scryfallIds.map((_) => '?').join(',');
    final result = await dbClient.rawQuery(
      'SELECT * FROM cards WHERE scryfall_id IN ($placeholders)',
      scryfallIds,
    );
    return result.map((map) => Card.fromMap(map)).toList();
  }

  Future<List<Card>> getBasicLands() async {
    final dbClient = await _db;
    final result = await dbClient.rawQuery(
      "SELECT * FROM cards WHERE name IN ('Plains','Island','Swamp','Mountain','Forest')",
    );
    return result.map((map) => Card.fromMap(map)).toList();
  }

  Future<Card?> getCardByName(String name) async {
    final dbClient = await _db;
    final lower = name.toLowerCase();

    // Exact full-name match takes priority over any split-card face match
    final exact = await dbClient.rawQuery(
      'SELECT * FROM cards WHERE lower(name) = ? LIMIT 1',
      [lower],
    );
    if (exact.isNotEmpty) return Card.fromMap(exact.first);

    // Front face (title) match
    final front = await dbClient.rawQuery(
      'SELECT * FROM cards WHERE lower(title) = ? LIMIT 1',
      [lower],
    );
    if (front.isNotEmpty) return Card.fromMap(front.first);

    // Back face match, only when no exact or front-face match was found
    final back = await dbClient.rawQuery(
      "SELECT * FROM cards WHERE lower(name) LIKE '% // ' || ? LIMIT 1",
      [lower],
    );
    if (back.isNotEmpty) return Card.fromMap(back.first);

    return null;
  }

  Future<List<Card>> getCardsByNames(List<String> names) async {
    if (names.isEmpty) return [];
    final lowerNames = names.map((n) => n.toLowerCase()).toList();
    final dbClient = await _db;
    final placeholders = lowerNames.map((_) => '?').join(',');
    final args = [...lowerNames, ...lowerNames];
    final result = await dbClient.rawQuery(
      'SELECT * FROM cards WHERE lower(name) IN ($placeholders) OR lower(title) IN ($placeholders)',
      args,
    );
    return result.map((map) => Card.fromMap(map)).toList();
  }

  Future<List<Map<String, String>>> getAllCardNames() async {
    final dbClient = await _db;
    final result = await dbClient.rawQuery('SELECT scryfall_id, name, title FROM cards');
    return result.map((r) => {
      'scryfall_id': r['scryfall_id'] as String,
      'name': r['name'] as String,
      'title': r['title'] as String,
    }).toList();
  }
}

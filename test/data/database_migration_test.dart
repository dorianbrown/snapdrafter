import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:snapdrafter/data/database/database_helper.dart';
import 'package:snapdrafter/data/database/backup_helper.dart';

/// Creates the schema as it existed at database version 7, before card
/// references moved from scryfall_id to oracle_id.
Future<Database> _createV7Database() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 7,
      singleInstance: false,
    ),
  );
  await db.execute("""
    CREATE TABLE cards(
      scryfall_id TEXT PRIMARY KEY,
      oracle_id TEXT NOT NULL,
      name TEXT NOT NULL,
      title TEXT NOT NULL,
      type TEXT NOT NULL,
      image_uri TEXT,
      colors TEXT,
      mana_cost TEXT,
      mana_value INTEGER NOT NULL,
      produced_mana TEXT,
      oracle_text TEXT
    )
  """);
  await db.execute("""
    CREATE TABLE decks(
      id INTEGER PRIMARY KEY,
      name TEXT,
      wins INTEGER,
      losses INTEGER,
      draws INTEGER,
      set_id TEXT,
      cubecobra_id STRING,
      image_path TEXT,
      ymd TEXT NOT NULL)
  """);
  await db.execute("""
    CREATE TABLE decklists(
      id INTEGER PRIMARY KEY,
      deck_id INTEGER NOT NULL,
      scryfall_id TEXT NOT NULL)
  """);
  await db.execute("""
    CREATE TABLE sideboard_lists(
      id INTEGER PRIMARY KEY,
      deck_id INTEGER NOT NULL,
      scryfall_id TEXT NOT NULL)
  """);
  await db.execute("""
    CREATE TABLE cubelists(
      id INTEGER PRIMARY KEY,
      cubecobra_id STRING NOT NULL,
      scryfall_id STRING NOT NULL)
  """);
  await db.execute("""
    CREATE TABLE tokens(
      oracle_id STRING PRIMARY KEY,
      name STRING NOT NULL,
      image_uri STRING NOT NULL)
  """);
  return db;
}

Future<void> _seedData(Database db) async {
  await db.execute(
      "INSERT INTO cards (scryfall_id, oracle_id, name, title, type, mana_value) VALUES "
      "('sid-a1', 'oid-A', 'Alpha Strike', 'Alpha Strike', 'Instant', 1), "
      "('sid-a2', 'oid-A', 'Alpha Strike', 'Alpha Strike', 'Instant', 1), "
      "('sid-b1', 'oid-B', 'Beta Blast', 'Beta Blast', 'Sorcery', 2), "
      "('sid-x1', 'oid-X', 'Gamma Gaze', 'Gamma Gaze', 'Instant', 1)");
  await db.execute(
      "INSERT INTO decks (id, name, ymd) VALUES (1, 'Deck One', '2026-01-01'), "
      "(2, 'Deck Two', '2026-01-02')");
  await db.execute("""
    INSERT INTO decklists (id, deck_id, scryfall_id) VALUES
      (1, 1, 'sid-a1'),
      (2, 1, 'sid-b1'),
      (3, 1, 'sid-x1'),
      (4, 2, 'sid-a2'),
      (5, 2, 'sid-b1'),
      (6, 2, 'sid-ghost')
  """);
  await db.execute(
      "INSERT INTO sideboard_lists (id, deck_id, scryfall_id) VALUES (1, 1, 'sid-b1')");
  await db.execute(
      "INSERT INTO cubelists (id, cubecobra_id, scryfall_id) VALUES "
      "(1, 'cube-1', 'sid-a1'), (2, 'cube-1', 'sid-ghost')");
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('v9 migration', () {
    test('migrates deck/cube references from scryfall_id to oracle_id '
        'and drops unresolvable rows', () async {
      final db = await _createV7Database();
      await _seedData(db);

      await DatabaseHelper.migrateDatabase(db, 7, 9);

      final decklistColumns = await db.rawQuery('PRAGMA table_info(decklists)');
      final decklistColumnNames =
          decklistColumns.map((c) => c['name']).toList();
      expect(decklistColumnNames, isNot(contains('scryfall_id')));
      expect(decklistColumnNames, contains('oracle_id'));

      final decklists = await db.rawQuery(
          'SELECT deck_id, oracle_id FROM decklists ORDER BY id');
      expect(decklists, [
        {'deck_id': 1, 'oracle_id': 'oid-A'},
        {'deck_id': 1, 'oracle_id': 'oid-B'},
        {'deck_id': 1, 'oracle_id': 'oid-X'},
        {'deck_id': 2, 'oracle_id': 'oid-B'},
      ], reason: 'unresolvable rows and rows referencing a deduped printing must be dropped');

      final sideboard = await db.rawQuery(
          'SELECT deck_id, oracle_id FROM sideboard_lists');
      expect(sideboard, [
        {'deck_id': 1, 'oracle_id': 'oid-B'},
      ]);

      final cubelists = await db.rawQuery(
          'SELECT cubecobra_id, oracle_id FROM cubelists ORDER BY id');
      expect(cubelists, [
        {'cubecobra_id': 'cube-1', 'oracle_id': 'oid-A'},
      ], reason: 'unresolvable scryfall_id row must be dropped');

      final indexes = await db.rawQuery(
          "PRAGMA index_list('cards')");
      final indexNames = indexes.map((i) => i['name']).toList();
      expect(indexNames, contains('idx_cards_oracle_id'));

      final uniqueFlags = indexes
          .where((i) => i['name'] == 'idx_cards_oracle_id')
          .map((i) => i['unique'])
          .toList();
      expect(uniqueFlags, [1]);

      await db.close();
    });

    test('v8 → v9 keeps ub columns and migrates references', () async {
      final db = await _createV7Database();
      await _seedData(db);

      // Simulate v8: add the ub artwork columns
      await db.execute('ALTER TABLE cards ADD ub_image_uri TEXT');
      await db.execute('ALTER TABLE cards ADD non_ub_image_uri TEXT');

      await DatabaseHelper.migrateDatabase(db, 8, 9);

      final cardColumns = await db.rawQuery('PRAGMA table_info(cards)');
      final cardColumnNames = cardColumns.map((c) => c['name']).toList();
      expect(cardColumnNames, containsAll(['ub_image_uri', 'non_ub_image_uri']));

      final decklists = await db.rawQuery(
          'SELECT deck_id, oracle_id FROM decklists ORDER BY id');
      expect(decklists, [
        {'deck_id': 1, 'oracle_id': 'oid-A'},
        {'deck_id': 1, 'oracle_id': 'oid-B'},
        {'deck_id': 1, 'oracle_id': 'oid-X'},
        {'deck_id': 2, 'oracle_id': 'oid-B'},
      ]);

      await db.close();
    });
  });

  group('BackupHelper.convertCardRefRow', () {
    test('keeps rows that already use oracle_id', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final row = await BackupHelper.convertCardRefRow(
          db, {'id': 1, 'deck_id': 1, 'oracle_id': 'oid-A'});
      expect(row, {'id': 1, 'deck_id': 1, 'oracle_id': 'oid-A'});
      await db.close();
    });

    test('resolves legacy scryfall_id rows against the cards table', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
          "CREATE TABLE cards (scryfall_id TEXT PRIMARY KEY, oracle_id TEXT NOT NULL, name TEXT)");
      await db.execute(
          "INSERT INTO cards VALUES ('sid-a1', 'oid-A', 'Alpha Strike')");

      final row = await BackupHelper.convertCardRefRow(
          db, {'id': 1, 'deck_id': 1, 'scryfall_id': 'sid-a1'});
      expect(row, {'id': 1, 'deck_id': 1, 'oracle_id': 'oid-A'});
      await db.close();
    });

    test('drops legacy rows whose card cannot be resolved', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
          "CREATE TABLE cards (scryfall_id TEXT PRIMARY KEY, oracle_id TEXT NOT NULL, name TEXT)");

      final row = await BackupHelper.convertCardRefRow(
          db, {'id': 1, 'deck_id': 1, 'scryfall_id': 'sid-ghost'});
      expect(row, isNull);
      await db.close();
    });
  });
}

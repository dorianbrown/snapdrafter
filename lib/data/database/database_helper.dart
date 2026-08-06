import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _databaseName = "draftTracker.db";
  static const int _databaseVersion = 9; // Latest db version after all upgrades

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePathRoot = Platform.isAndroid
        ? await getDatabasesPath()
        : (await getLibraryDirectory()).path;

    return await openDatabase(
      join(databasePathRoot, _databaseName),
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint("sqflite: Creating tables for version $version");
    // Decks and Cards
    await db.execute("""
      CREATE TABLE cards(
        scryfall_id TEXT PRIMARY KEY,
        oracle_id TEXT NOT NULL,
        name TEXT NOT NULL,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        image_uri TEXT,
        first_printing_image_uri TEXT,
        colors TEXT,
        mana_cost TEXT,
        mana_value INTEGER NOT NULL,
        produced_mana TEXT,
        oracle_text TEXT
      )
    """);
    // Cards are referenced by oracle id (one row per oracle card)
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_oracle_id ON cards(oracle_id)');
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
        oracle_id TEXT NOT NULL)
    """);
    // Sideboard table
    await db.execute("""
      CREATE TABLE sideboard_lists(
        id INTEGER PRIMARY KEY,
        deck_id INTEGER NOT NULL,
        oracle_id TEXT NOT NULL,
        FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE
      )
    """);
    // Token related tables
    await db.execute("""
      CREATE TABLE cards_to_tokens(
        card_oracle_id STRING NOT NULL,
        token_oracle_id STRING NOT NULL,
        PRIMARY KEY (card_oracle_id, token_oracle_id)
      )
    """);
    await db.execute("""
      CREATE TABLE tokens(
        oracle_id STRING PRIMARY KEY,
        name STRING NOT NULL,
        image_uri STRING NOT NULL,
        first_printing_image_uri STRING
      )
    """);
    // Card Collections
    await db.execute("""
      CREATE TABLE scryfall_metadata(
        id INTEGER PRIMARY KEY,
        datetime TEXT NOT NULL,
        newest_set_name TEXT NOT NULL
      )
    """);
    await db.execute("""
      CREATE TABLE sets(
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        released_at TEXT NOT NULL
      )
    """);
    await db.execute("""
      CREATE TABLE cubes(
        id INTEGER PRIMARY KEY,
        cubecobra_id TEXT NOT NULL,
        name TEXT NOT NULL,
        ymd TEXT NOT NULL
      )
    """);
    await db.execute("""
      CREATE TABLE cubelists(
        id INTEGER PRIMARY KEY,
        cubecobra_id STRING NOT NULL,
        oracle_id STRING NOT NULL
      )
    """);
    // Add tables for tags
    await db.execute("""
      CREATE TABLE tags(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      )
    """);
    await db.execute("""
      CREATE TABLE deck_tags(
        deck_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (deck_id, tag_id),
        FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    """);
    debugPrint("sqflite tables created");
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("sqflite: Upgrading tables from $oldVersion to $newVersion");
    await migrateDatabase(db, oldVersion, newVersion);
  }

  /// Applies all schema migrations between [oldVersion] and [newVersion].
  ///
  /// Exposed as a static method so migrations can be exercised against an
  /// in-memory database in tests.
  static Future<void> migrateDatabase(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("""
        CREATE TABLE IF NOT EXISTS cards_to_tokens(
          card_oracle_id STRING NOT NULL,
          token_oracle_id STRING NOT NULL,
          PRIMARY KEY (card_oracle_id, token_oracle_id)
        )
      """);
      await db.execute("""
        CREATE TABLE IF NOT EXISTS tokens(
          oracle_id STRING PRIMARY KEY,
          name STRING NOT NULL,
          image_uri STRING NOT NULL
        )
      """);
      // Check if column exists before adding, to make it idempotent
      var cardColumns = await db.rawQuery('PRAGMA table_info(cards)');
      bool hasProducedMana = cardColumns.any((col) => col['name'] == 'produced_mana');
      if (!hasProducedMana) {
        await db.execute("""
          ALTER TABLE cards
          ADD produced_mana TEXT
        """);
      }
      debugPrint("sqflite: Upgraded to V2");
    }
    if (oldVersion < 3) {
      await db.execute("""
      CREATE TABLE tags(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      )
      """);
      await db.execute("""
      CREATE TABLE deck_tags(
        deck_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (deck_id, tag_id),
        FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
      """);
    }
    if (oldVersion < 4) {
      await db.execute("""
        ALTER TABLE decks
        ADD image_path TEXT
      """);
      debugPrint("sqflite: Added image_path column to decks table");
    }

    if (oldVersion < 5) {  // Add support for sideboards in decks
      await db.execute("""
      CREATE TABLE sideboard_lists(
        id INTEGER PRIMARY KEY,
        deck_id INTEGER NOT NULL,
        scryfall_id TEXT NOT NULL
      )
      """);
    }

    if (oldVersion < 6) {
      // Add wins, losses, draws columns
      await db.execute("""
        ALTER TABLE decks ADD COLUMN wins INTEGER
      """);
      await db.execute("""
        ALTER TABLE decks ADD COLUMN losses INTEGER
      """);
      await db.execute("""
        ALTER TABLE decks ADD COLUMN draws INTEGER
      """);
      // Migrate data from win_loss column
      final rows = await db.rawQuery('SELECT id, win_loss FROM decks WHERE win_loss IS NOT NULL');
      for (final row in rows) {
        final id = row['id'] as int;
        final winLoss = row['win_loss'] as String?;
        int? wins, losses, draws;
        if (winLoss != null) {
          final parts = winLoss.split('/');
          if (parts.length >= 2) {
            wins = int.tryParse(parts[0]);
            losses = int.tryParse(parts[1]);
            draws = parts.length >= 3 ? int.tryParse(parts[2]) : 0;
          }
        }
        // Update with parsed values (null if parsing fails)
        await db.rawUpdate(
          'UPDATE decks SET wins = ?, losses = ?, draws = ? WHERE id = ?',
          [wins, losses, draws, id],
        );
      }

      // Remove the old win_loss column by creating a new table without it
      // Step 1: Create a new table with the current schema (without win_loss)
      await db.execute("""
        CREATE TABLE decks_new (
          id INTEGER PRIMARY KEY, 
          name TEXT,
          wins INTEGER,
          losses INTEGER,
          draws INTEGER,
          set_id TEXT,
          cubecobra_id STRING,
          image_path TEXT,
          ymd TEXT NOT NULL
        )
      """);

      // Step 2: Copy data from the old table to the new table
      await db.execute("""
        INSERT INTO decks_new (id, name, wins, losses, draws, set_id, cubecobra_id, image_path, ymd)
        SELECT id, name, wins, losses, draws, set_id, cubecobra_id, image_path, ymd
        FROM decks
      """);

      // Step 3: Drop the old table
      await db.execute("DROP TABLE decks");

      // Step 4: Rename the new table to the original name
      await db.execute("ALTER TABLE decks_new RENAME TO decks");
    }

    if (oldVersion < 7) {
      await db.execute("""
        ALTER TABLE cards
        ADD oracle_text TEXT
      """);
    }

    if (oldVersion < 8) {
      // Store the first (original) printing artwork per card/token
      var cardColumns = await db.rawQuery('PRAGMA table_info(cards)');
      if (!cardColumns.any((col) => col['name'] == 'first_printing_image_uri')) {
        await db.execute("""
          ALTER TABLE cards
          ADD first_printing_image_uri TEXT
        """);
      }
      var tokenColumns = await db.rawQuery('PRAGMA table_info(tokens)');
      if (!tokenColumns.any((col) => col['name'] == 'first_printing_image_uri')) {
        await db.execute("""
          ALTER TABLE tokens
          ADD first_printing_image_uri STRING
        """);
      }
      debugPrint("sqflite: Upgraded to V8");
    }

    if (oldVersion < 9) {
      // Cards are now referenced by oracle id (one row per oracle card),
      // instead of scryfall_id (a printing id that can change between
      // downloads). Deck and cube card references are migrated over, and
      // rows whose card can no longer be resolved are dropped.
      // Defensive: the cards table should already have one row per oracle
      // id, but dedupe anyway so the unique index below cannot fail.
      await db.execute("""
        DELETE FROM cards WHERE scryfall_id NOT IN (
          SELECT MIN(scryfall_id) FROM cards GROUP BY oracle_id
        )
      """);
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_oracle_id ON cards(oracle_id)');

      await db.execute("""
        CREATE TABLE decklists_new(
          id INTEGER PRIMARY KEY,
          deck_id INTEGER NOT NULL,
          oracle_id TEXT NOT NULL)
      """);
      await db.execute("""
        INSERT INTO decklists_new (id, deck_id, oracle_id)
        SELECT d.id, d.deck_id, c.oracle_id
        FROM decklists d
        INNER JOIN cards c ON c.scryfall_id = d.scryfall_id
      """);
      await db.execute('DROP TABLE decklists');
      await db.execute('ALTER TABLE decklists_new RENAME TO decklists');

      await db.execute("""
        CREATE TABLE sideboard_lists_new(
          id INTEGER PRIMARY KEY,
          deck_id INTEGER NOT NULL,
          oracle_id TEXT NOT NULL,
          FOREIGN KEY (deck_id) REFERENCES decks(id) ON DELETE CASCADE
        )
      """);
      await db.execute("""
        INSERT INTO sideboard_lists_new (id, deck_id, oracle_id)
        SELECT d.id, d.deck_id, c.oracle_id
        FROM sideboard_lists d
        INNER JOIN cards c ON c.scryfall_id = d.scryfall_id
      """);
      await db.execute('DROP TABLE sideboard_lists');
      await db.execute('ALTER TABLE sideboard_lists_new RENAME TO sideboard_lists');

      await db.execute("""
        CREATE TABLE cubelists_new(
          id INTEGER PRIMARY KEY,
          cubecobra_id STRING NOT NULL,
          oracle_id STRING NOT NULL)
      """);
      await db.execute("""
        INSERT INTO cubelists_new (id, cubecobra_id, oracle_id)
        SELECT d.id, d.cubecobra_id, c.oracle_id
        FROM cubelists d
        INNER JOIN cards c ON c.scryfall_id = d.scryfall_id
      """);
      await db.execute('DROP TABLE cubelists');
      await db.execute('ALTER TABLE cubelists_new RENAME TO cubelists');

      debugPrint("sqflite: Upgraded to V9");
    }

    // Add further migration steps for future versions here

  }

  Future<int?> countRows(String tableName) async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) FROM $tableName");
    return Sqflite.firstIntValue(result);
  }

}

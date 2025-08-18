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
  static const int _databaseVersion = 2; // Latest db version after all upgrades

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
        colors TEXT,
        mana_cost TEXT,
        mana_value INTEGER NOT NULL,
        produced_mana TEXT
      )
    """);
    await db.execute("""
      CREATE TABLE decks(
        id INTEGER PRIMARY KEY, 
        name TEXT,
        win_loss TEXT,
        set_id TEXT,
        cubecobra_id STRING,
        ymd TEXT NOT NULL)
    """);
    await db.execute("""
      CREATE TABLE decklists(
        id INTEGER PRIMARY KEY, 
        deck_id INTEGER NOT NULL, 
        scryfall_id TEXT NOT NULL)
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
        image_uri STRING NOT NULL
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
        scryfall_id STRING NOT NULL
      )
    """);
    debugPrint("sqflite tables created");
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("sqflite: Upgrading tables from $oldVersion to $newVersion");
    if (oldVersion < 2) { // Example: Migrating from V1 to V2
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
    // Add further migration steps for future versions here
    // if (oldVersion < 3) { ... }
  }

  Future<int?> countRows(String tableName) async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) FROM $tableName");
    return Sqflite.firstIntValue(result);
  }

  Future<Map<String, dynamic>> getScryfallMetadata() async {
    final db = await database;
    final result = await db.query("scryfall_metadata", limit: 1); // Ensure only one row
    return result.isNotEmpty ? result.first : {};
  }

}

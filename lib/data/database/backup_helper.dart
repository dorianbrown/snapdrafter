import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class BackupHelper {
  final DatabaseHelper _dbHelper;
  BackupHelper(this._dbHelper);
  Future<Database> get _db async => await _dbHelper.database;

  Future<Map<String, dynamic>> createBackupData() async {
    final dbClient = await _db;
    return {
      'cubes': await dbClient.query('cubes'),
      'cubelists': await dbClient.query('cubelists'),
      'decks': await dbClient.query('decks'),
      'decklists': await dbClient.query('decklists'),
    };
  }

  Future<void> restoreBackup(Map<String, dynamic> backupData) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      await txn.delete('decklists');
      await txn.delete('decks');
      await txn.delete('cubelists');
      await txn.delete('cubes');

      var batch = txn.batch();

      List<dynamic>? cubes = backupData['cubes'];
      if (cubes != null) {
        for (final cube in cubes) {
          batch.insert('cubes', cube as Map<String, Object?>);
        }
      }

      List<dynamic>? cubelists = backupData['cubelists'];
      if (cubelists != null) {
        for (final cubelist in cubelists) {
          batch.insert('cubelists', cubelist as Map<String, Object?>);
        }
      }

      List<dynamic>? decks = backupData['decks'];
      if (decks != null) {
        for (final deck in decks) {
          batch.insert('decks', deck as Map<String, Object?>);
        }
      }

      List<dynamic>? decklists = backupData['decklists'];
      if (decklists != null) {
        for (final decklist in decklists) {
          batch.insert('decklists', decklist as Map<String, Object?>);
        }
      }
      
      await batch.commit(noResult: true);
    });
  }
}

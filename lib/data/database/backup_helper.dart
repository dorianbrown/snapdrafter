import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'database_helper.dart';

class BackupHelper {
  late final DatabaseHelper _dbHelper;
  bool _dbHelperLoaded = false;

  // Make class singleton
  BackupHelper._privateConstructor();
  static final BackupHelper _instance = BackupHelper._privateConstructor();
  factory BackupHelper() {
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

  Future<Map<String, dynamic>> createBackupData() async {
    final dbClient = await _db;
    final directory = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${directory.path}/deck_images');
    
    Map<String, String> images = {};
    
    // Add images to backup if the directory exists
    if (imageDir.existsSync()) {
      final imageFiles = imageDir.listSync();
      for (var file in imageFiles) {
        if (file is File) {
          try {
            final bytes = await file.readAsBytes();
            images[file.uri.pathSegments.last] = base64Encode(bytes);
          } catch (e) {
            print('Error reading image ${file.path}: $e');
          }
        }
      }
    }

    return {
      'database': {
        'cubes': await dbClient.query('cubes'),
        'cubelists': await dbClient.query('cubelists'),
        'decks': await dbClient.query('decks'),
        'decklists': await dbClient.query('decklists'),
      },
      'images': images,
      'metadata': {
        'backup_version': 3,
        'created': DateTime.now().toIso8601String(),
      }
    };
  }

  Future<void> restoreBackup(Map<String, dynamic> backupData) async {
    final dbClient = await _db;
    
    // Detect backup format version
    final isLegacyFormat = backupData['database'] == null;
    final backupVersion = backupData['metadata']?['backup_version'] ?? 1;
    
    // Extract database data based on format
    final dbData = isLegacyFormat ? backupData : backupData['database'];
    
    await dbClient.transaction((txn) async {
      await txn.delete('decklists');
      await txn.delete('decks');
      await txn.delete('cubelists');
      await txn.delete('cubes');

      var batch = txn.batch();

      List<dynamic>? cubes = dbData['cubes'];
      if (cubes != null) {
        for (final cube in cubes) {
          batch.insert('cubes', cube as Map<String, Object?>);
        }
      }

      List<dynamic>? cubelists = dbData['cubelists'];
      if (cubelists != null) {
        for (final cubelist in cubelists) {
          final row =
              await convertCardRefRow(txn, Map.from(cubelist as Map<String, Object?>));
          if (row != null) {
            batch.insert('cubelists', row);
          }
        }
      }

      List<dynamic>? decks = dbData['decks'];
      if (decks != null) {
        for (final deck in decks) {
          Map<String, Object?> deckMap = Map.from(deck as Map<String, Object?>);
          // Convert old win_loss column to wins/losses/draws
          if (deckMap.containsKey('win_loss')) {
            final winLoss = deckMap['win_loss'] as String?;
            deckMap.remove('win_loss');
            int? wins, losses, draws;
            if (winLoss != null) {
              final parts = winLoss.split('/');
              if (parts.length >= 2) {
                wins = int.tryParse(parts[0]);
                losses = int.tryParse(parts[1]);
                draws = parts.length >= 3 ? int.tryParse(parts[2]) : 0;
              }
            }
            deckMap['wins'] = wins;
            deckMap['losses'] = losses;
            deckMap['draws'] = draws;
          }
          batch.insert('decks', deckMap);
        }
      }

      List<dynamic>? decklists = dbData['decklists'];
      if (decklists != null) {
        for (final decklist in decklists) {
          final row = await convertCardRefRow(
              txn, Map.from(decklist as Map<String, Object?>));
          if (row != null) {
            batch.insert('decklists', row);
          }
        }
      }
      
      await batch.commit(noResult: true);
    });

    // Handle images only if they exist in the backup (new format)
    if (backupVersion >= 2 && backupData['images'] != null) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final imageDir = Directory('${directory.path}/deck_images');
        
        // Clear existing images to avoid conflicts
        if (imageDir.existsSync()) {
          imageDir.deleteSync(recursive: true);
        }
        imageDir.createSync(recursive: true);
        
        final images = backupData['images'] as Map<String, dynamic>;
        for (var entry in images.entries) {
          try {
            final imageBytes = base64Decode(entry.value);
            final imageFile = File('${imageDir.path}/${entry.key}');
            await imageFile.writeAsBytes(imageBytes);
          } catch (e) {
            print('Error restoring image ${entry.key}: $e');
          }
        }
      } catch (e) {
        print('Error handling image restoration: $e');
      }
    }
    // For legacy backups (version 1), images remain untouched
  }

  /// Converts a backed-up decklist/cubelist row to the current schema.
  ///
  /// Backups from version 3 store card references as `oracle_id`. Legacy
  /// backups (versions 1-2) store `scryfall_id` (a printing id), which is
  /// resolved to the current `oracle_id` via the local cards table. Rows
  /// whose card cannot be resolved are dropped (returns null).
  static Future<Map<String, Object?>?> convertCardRefRow(
      DatabaseExecutor dbClient, Map<String, Object?> row) async {
    if (row.containsKey('oracle_id')) {
      return row;
    }
    final scryfallId = row.remove('scryfall_id');
    if (scryfallId is! String) return null;
    final result = await dbClient.rawQuery(
      'SELECT oracle_id FROM cards WHERE scryfall_id = ?',
      [scryfallId],
    );
    if (result.isEmpty) return null;
    row['oracle_id'] = result.first['oracle_id'];
    return row;
  }
}

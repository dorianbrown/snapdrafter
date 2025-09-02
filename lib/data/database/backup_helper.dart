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
        'backup_version': 2,
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
          batch.insert('cubelists', cubelist as Map<String, Object?>);
        }
      }

      List<dynamic>? decks = dbData['decks'];
      if (decks != null) {
        for (final deck in decks) {
          batch.insert('decks', deck as Map<String, Object?>);
        }
      }

      List<dynamic>? decklists = dbData['decklists'];
      if (decklists != null) {
        for (final decklist in decklists) {
          batch.insert('decklists', decklist as Map<String, Object?>);
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
}

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'package:collection/collection.dart'; // For groupFoldBy method
import '../models/token.dart'; // Adjust import path as needed

class TokenRepository {
  late final DatabaseHelper _dbHelper;
  bool _dbHelperLoaded = false;

  // Make class singleton
  TokenRepository._privateConstructor();
  static final TokenRepository _instance = TokenRepository._privateConstructor();
  factory TokenRepository() {
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

  Future<void> saveTokenList(List<Token> tokens, List<List<String>> cardTokenMapping) async {
    final dbClient = await _db;
    await dbClient.transaction((txn) async {
      var batch = txn.batch();
      for (final token in tokens) {
        batch.insert(
            "tokens",
            token.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      for (final obj in cardTokenMapping) {
        batch.insert(
            "cards_to_tokens",
            {
              "card_oracle_id": obj[0],
              "token_oracle_id": obj[1],
            },
            conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      batch.commit();
    });
  }

  Future<Map<String, dynamic>> getDeckTokens(int deckId) async {
    final dbClient = await _db;
    final result = await dbClient.rawQuery("""
      SELECT  
        C.name as card_name,  
        T.name as token_name,  
        T.image_uri as token_image
      FROM decklists D
        INNER JOIN cards C on D.scryfall_id = C.scryfall_id
        INNER JOIN cards_to_tokens CT on C.oracle_id = CT.card_oracle_id
        INNER JOIN tokens T on CT.token_oracle_id = T.oracle_id
      WHERE deck_id = ?
    """, [deckId]);

    // Return list of maps: str 'image', str 'name', list<str> 'cards'
    final resultsList = [for (final res in result) {
      "card_name": res["card_name"] as String,
      "token_name": res["token_name"] as String,
      "token_image": res["token_image"] as String,
    }];

    final groupedTokens = resultsList.groupFoldBy((obj) => obj["token_image"]!, (Map? obj1, Map obj2) {
      return obj1 == null
          ? {"name": obj2["token_name"], "cards": [obj2["card_name"]]}
          : {"name": obj1["token_name"], "cards": obj1["cards"] + [obj2["card_name"]]};
    });

    return groupedTokens;
  }

}

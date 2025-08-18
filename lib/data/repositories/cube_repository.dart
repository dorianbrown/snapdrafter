import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/cube.dart'; // Adjust import path
import '../models/card.dart'; // Adjust import path
import 'card_repository.dart'; // If you need to fetch full card objects

class CubeRepository {
  late final DatabaseHelper _dbHelper;
  late final CardRepository _cardRepository;

  CubeRepository() {
    _dbHelper = DatabaseHelper();
    _cardRepository = CardRepository();
  }

  Future<Database> get _db async => await _dbHelper.database;

  Future<List<Cube>> getAllCubes() async {
    final dbClient = await _db;
    final cubeResults = await dbClient.query("cubes");
    final cubeListsResults = await dbClient.query("cubelists");
    final allCards = await _cardRepository.getAllCards();

    List<Cube> outputList = [];

    for (final cubeRow in cubeResults) {
      final cubecobraId = cubeRow["cubecobra_id"] as String;
      final cardIdsForCube = cubeListsResults
          .where((cubeListRow) => cubeListRow["cubecobra_id"] == cubecobraId)
          .map((cubeListRow) => cubeListRow["scryfall_id"] as String?) // Make nullable
          .where((id) => id != null) // Filter out nulls
          .cast<String>() // Cast to non-nullable
          .toSet(); // Use a Set for efficient lookup

      final cubeCards = allCards.where((card) => cardIdsForCube.contains(card.scryfallId)).toList();

      outputList.add(Cube(
          cubecobraId: cubeRow["cubecobra_id"] as String,
          name: cubeRow["name"] as String,
          ymd: cubeRow["ymd"] as String,
          cards: cubeCards
      ));
    }
    return outputList;
  }

  Future<void> saveNewCube(String name, String ymd, String cubecobraId, List<Card> cards) async {
    final dbClient = await _db;
    await dbClient.insert(
      'cubes',
      {
        'name': name,
        'cubecobra_id': cubecobraId,
        'ymd': ymd
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await dbClient.transaction((txn) async {
      var batch = txn.batch();
      for (final card in cards) {
        batch.insert(
          'cubelists',
          {
            'cubecobra_id': cubecobraId,
            'scryfall_id': card.scryfallId
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit();
    });
  }

  Future<void> deleteCube(String cubecobraId) async {
    final dbClient = await _db;
     await dbClient.transaction((txn) async {
        // Removing references to this cubecobra_id in decks
        await txn.rawUpdate('UPDATE decks SET cubecobra_id = NULL WHERE cubecobra_id = ?', [cubecobraId]);
        await txn.delete(
          'cubelists',
          where: 'cubecobra_id = ?',
          whereArgs: [cubecobraId],
        );
        await txn.delete(
          'cubes',
          where: 'cubecobra_id = ?',
          whereArgs: [cubecobraId],
        );
    });
  }
}

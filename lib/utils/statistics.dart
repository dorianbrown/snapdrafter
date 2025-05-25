import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'utils.dart';
import 'models.dart';

class StatisticsRetriever {
  late Database _database;
  final String _databaseName = 'draftTracker.db';
  final int _databaseVersion = 1;

  StatisticsRetriever._privateConstructor();
  static final StatisticsRetriever _instance = StatisticsRetriever._privateConstructor();
  factory StatisticsRetriever() {
    return _instance;
  }

  Future<void> init() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), _databaseName),
      version: _databaseVersion
    );
  }

  Future getCardWinRates({String? setId, String? cubeId}) async {

    String queryId = setId != null
        ? 'set_id'
        : 'cubecobra_id';

    String queryValue = setId ?? cubeId!;

    String sqlQuery = """WITH tmp as (
    SELECT
        C.name,
        C.colors,
        CAST(SUBSTRING(D.win_loss, 1, 1) as double) as wins,
        CAST(SUBSTRING(D.win_loss, 3, 1) as double) as losses,
        D.win_loss
    FROM decks D
    INNER JOIN decklists DL on D.id = DL.deck_id
    INNER JOIN cards C on DL.scryfall_id = C.scryfall_id
    WHERE D.$queryId = '$queryValue'
        AND C.name NOT IN ('Plains', 'Island', 'Swamp', 'Mountain', 'Forest')
    )
    SELECT
        name as name,
        count(*) as num_decks,
        ROUND(SUM(wins) / SUM(wins + losses),2) as winrate
    FROM tmp
    GROUP BY Name
    ORDER BY winrate DESC""";

    final results = await _database.rawQuery(sqlQuery);

    return results;

  }
}

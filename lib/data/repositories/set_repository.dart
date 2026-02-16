import 'dart:async';
import 'dart:convert'; // For json.decode
import 'package:http/http.dart' as http; // For network requests
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:sqflite/sqflite.dart';

import '/data/database/database_helper.dart';
import '/data/models/set.dart';
import '/utils/utils.dart';


class SetRepository {
  late final DatabaseHelper _dbHelper;

  SetRepository() {
    _dbHelper = DatabaseHelper();
  }

  Future<Database> get _db async => await _dbHelper.database;

  Future<void> populateSetsTable() async {
    final response = await http.get(Uri.parse('https://api.scryfall.com/sets'));

    if (response.statusCode == 200) {
      final values = json.decode(response.body);
      String ymdString = convertDatetimeToYMD(DateTime.now(), sep: "-");
      final setsData = (values['data'] as List)
          .where((x) =>
              (["expansion", "core", "masters"].contains(x["set_type"])) &&
              (ymdString.compareTo(x["released_at"]) > 0) &&
              !x["digital"])
          .map((x) => {"code": x["code"], "name": x["name"], "released_at": x["released_at"]})
          .toList();

      final dbClient = await _db;
      await dbClient.transaction((txn) async {
        var batch = txn.batch();
        for (final setMap in setsData) {
          batch.insert(
            "sets",
            setMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit();
      });
      debugPrint("Added ${setsData.length} sets to sets table");
    } else {
      throw Exception('Failed to load sets from Scryfall API');
    }
  }

  Future<Map<String, DateTime>> fetchUpcomingReleaseDates() async {
    final response = await http.get(Uri.parse('https://api.scryfall.com/sets'));

    final validSetTypes = ["expansion", "core", "masters"];

    if (response.statusCode == 200) {
      final values = json.decode(response.body);
      final now = DateTime.now();
      final upcomingDates = <String, DateTime>{};
      
      for (final setData in values['data'] as List) {
        final releasedAt = setData["released_at"];
        final setType = setData["set_type"];
        if (
          releasedAt != null &&
          validSetTypes.contains(setType) &&
          (setData["digital"] == false)
        ) {
          final releaseDate = DateTime.parse(releasedAt);
          // Only store future dates (add 8 days buffer like in download_screen)
          final bufferDate = releaseDate.add(const Duration(days: 8));
          if (bufferDate.isAfter(now)) {
            upcomingDates[setData["code"]] = releaseDate;
          }
        }
      }
      
      debugPrint("Fetched ${upcomingDates.length} upcoming release dates");
      return upcomingDates;
    } else {
      throw Exception('Failed to load sets from Scryfall API');
    }
  }

  Future<List<Set>> getAllSets() async {
    final dbClient = await _db;
    final result = await dbClient.query('sets');
    return [
      for (final {
      "code": code as String,
      "name": name as String,
      "released_at": releasedAt as String,
      } in result)
        Set(
            code: code,
            name: name,
            releasedAt: releasedAt
        )
    ];
  }

  Future<Map<String, dynamic>> getScryfallMetadata() async {
    final db = await _db;
    final result = await db.query("scryfall_metadata", limit: 1); // Ensure only one row
    return result.isNotEmpty ? result.first : {};
  }
}

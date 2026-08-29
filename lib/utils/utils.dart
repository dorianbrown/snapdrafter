import 'dart:convert';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import 'package:fuzzywuzzy/ratios/simple_ratio.dart';
import 'package:http/http.dart' as http;

import 'package:snapdrafter/data/models/card.dart';
import 'package:snapdrafter/data/repositories/card_repository.dart';

class CubecobraCubeData {
  final String name;
  final List<Card> cards;

  const CubecobraCubeData({required this.name, required this.cards});
}

enum CaptureSource { camera, gallery, share }

String convertDatetimeToYMDHM(DateTime datetime) {
  String outputString = datetime.year.toString().substring(0,4);
  outputString += "-${datetime.month.toString().padLeft(2,'0')}";
  outputString += "-${datetime.day.toString().padLeft(2,'0')}";
  outputString += " ${datetime.hour.toString().padLeft(2,'0')}";
  outputString += ":${datetime.minute.toString().padLeft(2,'0')}";
  return outputString;
}

String convertDatetimeToYMD(DateTime datetime, {String sep = "-"}) {
  String outputString = datetime.year.toString();
  outputString += "$sep${datetime.month.toString().padLeft(2,'0')}";
  outputString += "$sep${datetime.day.toString().padLeft(2,'0')}";
  return outputString;
}

String formatDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return "";
  if (start == null) return formatSingleDate(end!);
  if (end == null) return formatSingleDate(start);
  
  if (start.year == end.year) {
    if (start.month == end.month) {
      return "${start.day} - ${end.day} ${_getMonthName(start.month)} ${start.year}";
    }
    return "${start.day} ${_getMonthName(start.month)} - ${end.day} ${_getMonthName(end.month)} ${start.year}";
  }
  return "${formatSingleDate(start)} - ${formatSingleDate(end)}";
}

String formatSingleDate(DateTime date) {
  return "${date.day} ${_getMonthName(date.month)} ${date.year}";
}

String _getMonthName(int month) {
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", 
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return months[month - 1];
}

bool validateDateTimeString(String datetimeString) {
  final regex = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$');
  return datetimeString.isNotEmpty && !regex.hasMatch(datetimeString);
}

bool regexValidator(String input, String pattern) {
  final regex = RegExp(pattern);
  return input.isNotEmpty && !regex.hasMatch(input);
}

class MatchParams {
  final String query;
  final List<String> choices;

  MatchParams({required this.query, required this.choices});
}

ExtractedResult<String> runFuzzyMatch(MatchParams params) {
  final match = extractOne(
    query: params.query,
    choices: params.choices,
    ratio: SimpleRatio()
  );
  return match;
}

Future<CubecobraCubeData> fetchCubecobraCube(String cubecobraId) async {
  CardRepository cardRepository = CardRepository();

  final response = await http.get(
    Uri.parse("https://cubecobra.com/cube/api/cubeJSON/$cubecobraId"),
    headers: {'User-Agent': 'SnapDrafter/1.0', 'Accept': '*/*'}
  );
  if (response.statusCode == 200) {
    final cube = jsonDecode(response.body) as Map<String, dynamic>;
    final cardsData = cube['cards'] as Map<String, dynamic>? ?? {};
    final mainboard = cardsData['mainboard'] as List<dynamic>? ?? [];
    final cubeList = [
      for (final card in mainboard)
        if (card is Map<String, dynamic> &&
            card['details'] is Map<String, dynamic> &&
            (card['details'] as Map<String, dynamic>)['name'] is String)
          (card['details'] as Map<String, dynamic>)['name'] as String,
    ];
    final cards = await cardRepository.getCardsByNames(cubeList);
    return CubecobraCubeData(
      name: cube['name'] as String? ?? cubecobraId,
      cards: cards,
    );
  } else {
    throw Exception('Failed to load cube list');
  }
}

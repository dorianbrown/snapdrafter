import 'dart:convert';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import 'package:fuzzywuzzy/ratios/simple_ratio.dart';
import 'package:http/http.dart' as http;

import 'package:snapdrafter/data/models/card.dart';
import 'package:snapdrafter/data/repositories/card_repository.dart';

import 'models.dart';

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

Future<List<Card>> fetchCubecobraList(String cubecobraId) async {

  CardRepository cardRepository = CardRepository();

  String uri = "https://cubecobra.com/cube/api/cubecardnames/$cubecobraId/mainboard";
  final response = await http.get(Uri.parse(uri));
  if (response.statusCode == 200) {
    final body = jsonDecode(response.body);
    List<String> cubeList = unpackCubeMap(body["cardnames"]);
    final cards = await cardRepository.getAllCards();
    // With double sided cards cubecobra only used front side. This solves the issue,
    // but might cause some issues in the future.
    return cards.where((card) => cubeList.contains(card.name) || cubeList.contains(card.title)).toList();
  } else {
    throw Exception('Failed to load album');
  }
}

List<String> unpackCubeMap(Map<String, dynamic> map) {

  List<String> tailList = [];

  for (String key in map.keys) {
    if (key == "\$") {
      tailList += [""];
    } else {
      final tails = unpackCubeMap(map[key]);
      tailList += tails.map((tail) => "$key$tail").toList();
    }
  }
  return tailList;
}

import 'package:fuzzywuzzy/algorithms/weighted_ratio.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';
import 'package:fuzzywuzzy/ratios/partial_ratio.dart';
import 'package:fuzzywuzzy/ratios/simple_ratio.dart';

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
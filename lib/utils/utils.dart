import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/model/extracted_result.dart';

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

int fuzzyMatch(String query, List<String> choices) {
  ExtractedResult<String> match = extractOne(query: query, choices: choices);
  return match.index;
}
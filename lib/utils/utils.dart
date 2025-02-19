String convertDatetimeToString(DateTime datetime) {
  String outputString = datetime.year.toString();
  outputString += "/${datetime.month.toString().padLeft(2,'0')}";
  outputString += "/${datetime.day.toString().padLeft(2,'0')}";
  outputString += " ${datetime.hour.toString().padLeft(2,'0')}";
  outputString += ":${datetime.minute.toString().padLeft(2,'0')}";
  return outputString;
}
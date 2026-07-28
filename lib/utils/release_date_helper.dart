import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ReleaseDateHelper {
  static const String _upcomingReleaseDatesKey = 'upcoming_release_dates';
  static const String _lastFetchedKey = 'last_fetched_timestamp';
  static const String _promptedDatesKey = 'prompted_release_dates';
  static const Duration _cacheDuration = Duration(days: 7);
  
  Future<Map<String, DateTime>> getUpcomingReleaseDates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_upcomingReleaseDatesKey);
    if (jsonString == null) return {};
    
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return jsonMap.map((key, value) => 
          MapEntry(key, DateTime.parse(value as String)));
    } catch (e) {
      return {};
    }
  }
  
  Future<void> saveUpcomingReleaseDates(Map<String, DateTime> dates) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = dates.map((key, value) => 
        MapEntry(key, value.toIso8601String()));
    final jsonString = jsonEncode(jsonMap);
    await prefs.setString(_upcomingReleaseDatesKey, jsonString);
    await prefs.setInt(_lastFetchedKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  Future<Set<String>> getPromptedSets() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_promptedDatesKey);
    if (jsonString == null) return {};
    
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return Set<String>.from(list.cast<String>());
    } catch (e) {
      return {};
    }
  }
  
  Future<void> addToPromptedDates(String setCode) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getPromptedSets();
    current.add(setCode);
    await prefs.setString(_promptedDatesKey, jsonEncode(current.toList()));
  }
  
  Future<bool> shouldFetchNewDates() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetched = prefs.getInt(_lastFetchedKey);
    if (lastFetched == null) return true;
    
    final lastFetchedTime = DateTime.fromMillisecondsSinceEpoch(lastFetched);
    return DateTime.now().difference(lastFetchedTime) > _cacheDuration;
  }
  
  Future<void> clearPassedDates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_promptedDatesKey);
  }
}

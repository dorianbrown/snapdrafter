import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class ChangelogEntry {
  const ChangelogEntry({required this.version, required this.body});

  final String version;
  final String body;

  String get markdown => '## $version\n$body';
}

class ChangelogHelper {
  static const String changelogAssetPath = 'assets/changelog/CHANGELOG.md';
  static const String lastSeenVersionKey = 'last_seen_changelog_version';

  static Future<List<ChangelogEntry>> loadChangelog() async {
    final raw = await rootBundle.loadString(changelogAssetPath);
    return parseChangelog(raw);
  }

  static List<ChangelogEntry> parseChangelog(String raw) {
    final entries = <ChangelogEntry>[];
    final headerPattern = RegExp(r'^##\s+(.+?)\s*$');
    ChangelogEntry? current;
    final bodyBuffer = StringBuffer();

    void flush() {
      final entry = current;
      if (entry != null) {
        entries.add(ChangelogEntry(
          version: entry.version,
          body: bodyBuffer.toString().trim(),
        ));
      }
      bodyBuffer.clear();
    }

    for (final line in raw.split('\n')) {
      final match = headerPattern.firstMatch(line);
      if (match != null) {
        flush();
        current = ChangelogEntry(
          version: match.group(1)!.trim(),
          body: bodyBuffer.toString(),
        );
      } else if (current != null) {
        bodyBuffer.writeln(line);
      }
    }
    flush();
    return entries;
  }

  static List<ChangelogEntry> entriesAfter(
      List<ChangelogEntry> entries, String? lastSeenVersion) {
    if (lastSeenVersion == null || lastSeenVersion.isEmpty) return entries;
    return entries
        .where((entry) {
          final comparison = compareVersions(entry.version, lastSeenVersion);
          return comparison != null && comparison > 0;
        })
        .toList();
  }

  static int? compareVersions(String a, String b) {
    final aParts = a.split('+').first.split('.').map(int.tryParse).toList();
    final bParts = b.split('+').first.split('.').map(int.tryParse).toList();
    if (aParts.any((part) => part == null) ||
        bParts.any((part) => part == null)) {
      return null;
    }

    final length = max(aParts.length, bParts.length);
    for (var i = 0; i < length; i++) {
      final aValue = i < aParts.length ? aParts[i]! : 0;
      final bValue = i < bParts.length ? bParts[i]! : 0;
      if (aValue != bValue) return aValue < bValue ? -1 : 1;
    }
    return 0;
  }

  static Future<String?> getLastSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastSeenVersionKey);
  }

  static Future<void> saveLastSeenVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastSeenVersionKey, version);
  }
}

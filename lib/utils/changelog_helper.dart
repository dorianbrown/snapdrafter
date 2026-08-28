import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.body,
    this.date,
  });

  final String version;
  final String body;
  final String? date;

  String get markdown {
    final dateLine = date == null ? '' : '`$date`\n\n';
    return '$dateLine## $version\n$body';
  }
}

class ChangelogHrPaddingBuilder extends MarkdownPaddingBuilder {
  ChangelogHrPaddingBuilder();

  @override
  EdgeInsets getPadding() => const EdgeInsets.symmetric(vertical: 20);
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
    final datePattern = RegExp(r'^`(\d{4}-\d{2}-\d{2})`$');
    ChangelogEntry? current;
    final bodyBuffer = StringBuffer();

    void flush() {
      final entry = current;
      if (entry != null) {
        entries.add(ChangelogEntry(
          version: entry.version,
          body: bodyBuffer.toString().trim(),
          date: entry.date,
        ));
      }
      bodyBuffer.clear();
    }

    for (final line in raw.split('\n')) {
      final match = headerPattern.firstMatch(line);
      if (match != null) {
        final lines = bodyBuffer.toString().split('\n');
        var i = lines.length - 1;
        while (i >= 0 && lines[i].trim().isEmpty) {
          i--;
        }
        String? date;
        if (i >= 0) {
          final dateMatch = datePattern.firstMatch(lines[i].trim());
          if (dateMatch != null) {
            date = dateMatch.group(1);
          }
        }
        final previousBody =
            (date != null ? lines.sublist(0, i) : lines).join('\n');
        bodyBuffer.clear();
        bodyBuffer.write(previousBody);
        flush();
        current = ChangelogEntry(
          version: match.group(1)!.trim(),
          body: '',
          date: date,
        );
        bodyBuffer.clear();
      } else {
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

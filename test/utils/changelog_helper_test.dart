import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/changelog_helper.dart';

void main() {
  const sampleChangelog = '''
# SnapDrafter Changelog

## 1.2.2
- Simplified BLE connections
- Fixed light mode issues

## 1.2.0
- Added a debug mode

## 1.0.0
- Released!
''';

  group('parseChangelog', () {
    test('parses version headers and bodies in order', () {
      final entries = ChangelogHelper.parseChangelog(sampleChangelog);
      expect(entries.length, 3);
      expect(entries[0].version, '1.2.2');
      expect(entries[0].body, contains('Simplified BLE connections'));
      expect(entries[1].version, '1.2.0');
      expect(entries[2].version, '1.0.0');
    });

    test('ignores content above the first version header', () {
      final entries = ChangelogHelper.parseChangelog(sampleChangelog);
      expect(entries[0].body, isNot(contains('SnapDrafter')));
    });

    test('returns empty list for empty input', () {
      expect(ChangelogHelper.parseChangelog(''), isEmpty);
    });

    test('builds markdown with version header prefix', () {
      final entries = ChangelogHelper.parseChangelog(sampleChangelog);
      expect(entries[0].markdown, startsWith('## 1.2.2\n'));
    });
  });

  group('compareVersions', () {
    test('compares equal versions', () {
      expect(ChangelogHelper.compareVersions('1.2.2', '1.2.2'), 0);
    });

    test('compares numerically across all parts', () {
      expect(ChangelogHelper.compareVersions('1.2.11', '1.2.2'), 1);
      expect(ChangelogHelper.compareVersions('1.2.2', '1.2.11'), -1);
      expect(ChangelogHelper.compareVersions('1.10.0', '2.0.0'), -1);
    });

    test('ignores build metadata', () {
      expect(ChangelogHelper.compareVersions('1.2.2+43', '1.2.2'), 0);
      expect(
          ChangelogHelper.compareVersions('1.2.209', '1.2.2'), 1);
    });

    test('treats missing parts as zero', () {
      expect(ChangelogHelper.compareVersions('1.2', '1.2.0'), 0);
      expect(ChangelogHelper.compareVersions('1.2', '1.2.1'), -1);
    });

    test('returns null for non-numeric versions', () {
      expect(ChangelogHelper.compareVersions('1.2.a', '1.2.2'), isNull);
    });
  });

  group('entriesAfter', () {
    final entries = ChangelogHelper.parseChangelog(sampleChangelog);

    test('returns all entries when last seen version is null', () {
      expect(ChangelogHelper.entriesAfter(entries, null), entries);
    });

    test('returns only newer entries', () {
      final result = ChangelogHelper.entriesAfter(entries, '1.2.0');
      expect(result.map((e) => e.version), ['1.2.2']);
    });

    test('returns nothing when already up to date', () {
      expect(ChangelogHelper.entriesAfter(entries, '1.2.2'), isEmpty);
      expect(ChangelogHelper.entriesAfter(entries, '99.0.0'), isEmpty);
    });

    test('keeps changelog ordering (newest first)', () {
      final result = ChangelogHelper.entriesAfter(entries, '1.0.0');
      expect(result.map((e) => e.version), ['1.2.2', '1.2.0']);
    });
  });
}

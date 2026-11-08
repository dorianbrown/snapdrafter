import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/changelog_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every changelog entry has a date, version and 1-3 sections', () async {
    final entries = await ChangelogHelper.loadChangelog();
    const allowedSections = {'Features', 'Bugfixes', 'Other'};
    final sectionPattern = RegExp(r'^####\s+(.+?)\s*$', multiLine: true);
    final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

    expect(entries, isNotEmpty);

    for (final entry in entries) {
      final version = entry.version;
      final sections = sectionPattern
          .allMatches(entry.body)
          .map((match) => match.group(1)!.trim())
          .toList();

      expect(entry.date, isNotNull, reason: '$version has no date');
      expect(
        entry.date!,
        matches(datePattern),
        reason: '$version has a malformed date: ${entry.date}',
      );
      expect(
        version,
        matches(versionPattern),
        reason: '$version is not a valid version number',
      );

      expect(
        sections,
        isNotEmpty,
        reason: '$version has no Features, Bugfixes or Other section',
      );
      expect(
        sections.toSet().length,
        sections.length,
        reason: '$version has duplicate sections: $sections',
      );
      expect(
        sections.length,
        lessThanOrEqualTo(3),
        reason: '$version has more than three sections: $sections',
      );

      for (final section in sections) {
        expect(
          allowedSections,
          contains(section),
          reason: '$version has an unknown section: $section',
        );
      }

      expect(entry.body, isNotEmpty, reason: '$version has an empty body');
    }
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/utils/changelog_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real changelog asset parses into expected sections', () async {
    final entries = await ChangelogHelper.loadChangelog();

    expect(entries.length, 17);
    expect(entries.first.version, '1.2.2');
    expect(entries.last.version, '0.6.0');

    final first = entries.first.body;
    expect(first, contains('#### Features'));
    expect(first, contains('#### Bugfixes'));
    expect(first, contains('#### Other'));

    final last = entries.last.body;
    expect(last, contains('#### Features'));
    expect(last, contains('#### Bugfixes'));
    expect(last, isNot(contains('#### Other')));

    final single = entries.firstWhere((e) => e.version == '1.1.9').body;
    expect(single, isNot(contains('#### Features')));
    expect(single, contains('#### Bugfixes'));

    expect(entries.every((e) => e.body.isNotEmpty), isTrue);
  });
}

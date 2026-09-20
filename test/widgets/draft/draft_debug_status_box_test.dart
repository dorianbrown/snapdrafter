import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snapdrafter/services/draft/draft_session_notifier.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/widgets/draft/draft_debug_status_box.dart';

import '../../services/draft/draft_session_notifier_test.dart';

Widget _wrap(DraftSessionNotifier notifier) {
  return ChangeNotifierProvider.value(
    value: notifier,
    child: const MaterialApp(home: Scaffold(body: DraftDebugStatusBox())),
  );
}

DraftState _lobbyState() => DraftState.create(
  name: 'Debug Draft',
  leaderDeviceId: 'leader-device',
  leaderPlayerName: 'Host',
  seatCount: 4,
);

void main() {
  testWidgets('hidden when debug mode is disabled', (tester) async {
    SharedPreferences.setMockInitialValues({'debug_enabled': false});
    final notifier = DraftSessionNotifier(myDeviceId: 'guest');
    notifier.state = _lobbyState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    expect(find.textContaining('DEBUG'), findsNothing);
  });

  testWidgets('host shows role, sequence, phase and links', (tester) async {
    SharedPreferences.setMockInitialValues({'debug_enabled': true});
    final fakeLeader = FakeDraftBleLeader();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => fakeLeader,
    );
    await notifier.createAndHost(
      name: 'Debug Draft',
      seatCount: 4,
      playerName: 'Host',
    );

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    expect(find.textContaining('DEBUG host'), findsOneWidget);
    expect(find.textContaining('seq 0'), findsOneWidget);
    expect(find.textContaining('lobby'), findsOneWidget);
    expect(find.textContaining('links 0'), findsOneWidget);
  });

  testWidgets('leaf shows parent when debug mode is enabled', (tester) async {
    SharedPreferences.setMockInitialValues({'debug_enabled': true});
    final notifier = DraftSessionNotifier(myDeviceId: 'guest');
    notifier.state = _lobbyState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    expect(find.textContaining('DEBUG leaf'), findsOneWidget);
    expect(find.textContaining('parent -'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';
import 'package:snapdrafter/screens/draft/draft_active.dart';

import '../../services/draft/draft_session_notifier_test.dart';

DraftState _leaderState() {
  final playerA = DraftPlayer(
    deviceId: 'leader-device',
    deviceName: 'Leader',
    playerName: 'Host',
    status: PlayerStatus.accepted,
    joinOrder: 0,
  );
  final playerB = DraftPlayer(
    deviceId: 'player-b',
    deviceName: 'Device B',
    playerName: 'Player B',
    status: PlayerStatus.accepted,
    joinOrder: 1,
  );

  return DraftState.create(
    name: 'Active Draft',
    leaderDeviceId: 'leader-device',
    leaderPlayerName: 'Host',
    seatCount: 4,
  ).copyWith(
    session: DraftState.create(
      name: 'Active Draft',
      leaderDeviceId: 'leader-device',
      leaderPlayerName: 'Host',
      seatCount: 4,
    ).session.copyWith(
      phase: DraftPhase.inProgress,
      totalRounds: 3,
    ),
    players: [playerA, playerB],
    rounds: [
      DraftRound(
        roundNumber: 1,
        matches: [
          DraftMatch(
            matchId: 'r1_m0',
            roundNumber: 1,
            playerAId: 'leader-device',
            playerBId: 'player-b',
          ),
        ],
        roundStartTime: DateTime.now(),
        complete: false,
      ),
    ],
  );
}

DraftSessionNotifier _createLeaderNotifier({
  required FakeDraftBleLeader fakeLeader,
}) {
  final notifier = DraftSessionNotifier(
    myDeviceId: 'leader-device',
    bleLeaderFactory: () => fakeLeader,
  );
  fakeLeader.connectedDevices.add('dummy');
  notifier.state = _leaderState();
  return notifier;
}

DraftSessionNotifier _createFollowerNotifier({
  required FakeDraftBleFollower fakeFollower,
}) {
  final notifier = DraftSessionNotifier(
    myDeviceId: 'player-b',
    bleFollowerFactory: () => fakeFollower,
  );
  notifier.state = _leaderState();
  return notifier;
}

Widget _wrap(DraftSessionNotifier notifier) {
  return MaterialApp(
    home: ChangeNotifierProvider.value(
      value: notifier,
      child: const DraftActiveScreen(),
    ),
  );
}

void main() {
  group('DraftActiveScreen — leader view', () {
    late FakeDraftBleLeader fakeLeader;
    late DraftSessionNotifier notifier;

    setUp(() {
      fakeLeader = FakeDraftBleLeader();
      fakeLeader.connectedDevices.add('dummy');
      notifier = _createLeaderNotifier(fakeLeader: fakeLeader);
    });

    testWidgets('shows draft name in app bar', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.widgetWithText(AppBar, 'Active Draft'), findsOneWidget);
    });

    testWidgets('shows round header', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.textContaining('Round '), findsOneWidget);
    });

    testWidgets('shows round number correctly', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.textContaining('Round 1'), findsOneWidget);
      expect(find.textContaining('/ 3'), findsOneWidget);
    });

    testWidgets('shows opponent match tile', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Player B'), findsOneWidget);
    });

    testWidgets('shows standings icon in app bar', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.byIcon(Icons.leaderboard), findsOneWidget);
    });

    testWidgets('FAB shows Report Match Result when leader can report', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      // Leader has a match with Player B and round is not complete,
      // so the FAB priority is: report result before standings.
      expect(find.text('Report Match Result'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
    });
  });

  group('DraftActiveScreen — follower view', () {
    late FakeDraftBleFollower fakeFollower;
    late DraftSessionNotifier notifier;

    setUp(() {
      fakeFollower = FakeDraftBleFollower();
      notifier = _createFollowerNotifier(fakeFollower: fakeFollower);
    });

    testWidgets('shows opponent card', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Your Opponent'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
    });

    testWidgets('shows match status section', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Match Status'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';
import 'package:snapdrafter/screens/draft/draft_management.dart';

import '../../services/draft/draft_session_notifier_test.dart';

DraftSessionNotifier _createLeader({
  required FakeDraftBleLeader fakeLeader,
  String name = 'Test Draft',
  int seatCount = 8,
  int acceptedPlayers = 4,
}) {
  final notifier = DraftSessionNotifier(
    myDeviceId: 'leader-device',
    bleLeaderFactory: () => fakeLeader,
  );

  final state = DraftState.create(
    name: name,
    leaderDeviceId: 'leader-device',
    leaderPlayerName: 'Host',
    seatCount: seatCount,
  );

  final players = <DraftPlayer>[
    DraftPlayer(
      deviceId: 'leader-device',
      playerName: 'Host',
      status: PlayerStatus.accepted,
      joinOrder: 0,
    ),
  ];
  for (var i = 0; i < acceptedPlayers - 1 && i < 4; i++) {
    final id = 'player-$i';
    players.add(
      DraftPlayer(
        deviceId: id,
        playerName: 'Player ${i + 1}',
        status: PlayerStatus.accepted,
        joinOrder: i + 1,
      ),
    );
  }

  fakeLeader.connectedDevices.add('dummy');
  notifier.state = state.copyWith(players: players);

  return notifier;
}

Widget _wrap(DraftSessionNotifier notifier) {
  return MaterialApp(
    home: ChangeNotifierProvider.value(
      value: notifier,
      child: const DraftManagementScreen(),
    ),
  );
}

void main() {
  late FakeDraftBleLeader fakeLeader;
  late DraftSessionNotifier notifier;

  setUp(() {
    fakeLeader = FakeDraftBleLeader();
    notifier = _createLeader(fakeLeader: fakeLeader);
  });

  group('DraftManagementScreen', () {
    testWidgets('shows draft name in app bar', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.widgetWithText(AppBar, 'Test Draft'), findsOneWidget);
    });

    testWidgets('shows player list', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Player 1'), findsOneWidget);
      expect(find.text('Player 2'), findsOneWidget);
      expect(find.text('Player 3'), findsOneWidget);
    });

    testWidgets('shows player count header', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Players (4)'), findsOneWidget);
    });

    testWidgets('shows draft configuration', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Draft Configuration'), findsOneWidget);
      expect(find.text('Name:'), findsOneWidget);
    });

    testWidgets('shows session ID in monospace', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Session ID:'), findsOneWidget);
    });

    testWidgets('FAB shows Start Draft', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.text('Start Draft'), findsOneWidget);
    });

    testWidgets('FAB has play arrow icon', (tester) async {
      await tester.pumpWidget(_wrap(notifier));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('FAB is disabled when lobby is not full', (tester) async {
      final underfilled = _createLeader(
        fakeLeader: fakeLeader,
        seatCount: 8,
        acceptedPlayers: 2,
      );
      await tester.pumpWidget(_wrap(underfilled));

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
    });

    testWidgets('FAB is enabled when lobby is full', (tester) async {
      final full = _createLeader(
        fakeLeader: fakeLeader,
        seatCount: 4,
        acceptedPlayers: 4,
      );
      await tester.pumpWidget(_wrap(full));

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNotNull);
    });

    testWidgets('shows waiting message when no players', (tester) async {
      final empty = _createLeader(fakeLeader: fakeLeader, acceptedPlayers: 1);
      empty.state = empty.state!.copyWith(players: []);

      await tester.pumpWidget(_wrap(empty));
      expect(find.text('Waiting for players to join...'), findsOneWidget);
    });

    testWidgets('FAB has correct background color when enabled', (
      tester,
    ) async {
      final full = _createLeader(
        fakeLeader: fakeLeader,
        seatCount: 4,
        acceptedPlayers: 4,
      );
      await tester.pumpWidget(_wrap(full));

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.backgroundColor, Colors.green);
    });
  });
}

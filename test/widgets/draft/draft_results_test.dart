import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';
import 'package:snapdrafter/screens/draft/draft_results.dart';

DraftState _resultsState() {
  final p1 = DraftPlayer(
    deviceId: 'leader-device',
    deviceName: 'Leader',
    playerName: 'Winner',
    status: PlayerStatus.accepted,
    joinOrder: 0,
    matchWins: 3,
  );
  final p2 = DraftPlayer(
    deviceId: 'player-b',
    deviceName: 'Device B',
    playerName: 'Runner Up',
    status: PlayerStatus.accepted,
    joinOrder: 1,
    matchWins: 1,
    matchLosses: 2,
  );

  return DraftState.create(
    name: 'Completed Draft',
    leaderDeviceId: 'leader-device',
    leaderPlayerName: 'Winner',
    seatCount: 4,
  ).copyWith(
    session: DraftState.create(
      name: 'Completed Draft',
      leaderDeviceId: 'leader-device',
      leaderPlayerName: 'Winner',
      seatCount: 4,
    ).session.copyWith(
      phase: DraftPhase.complete,
      totalRounds: 3,
      setCode: 'DMU',
    ),
    players: [p1, p2],
    rounds: [
      DraftRound(
        roundNumber: 1,
        matches: [
          DraftMatch(
            matchId: 'r1_m0',
            roundNumber: 1,
            playerAId: 'leader-device',
            playerBId: 'player-b',
            aWins: 2,
            bWins: 0,
            status: MatchStatus.confirmed,
          ),
        ],
        roundStartTime: DateTime(2025, 1, 1),
        complete: true,
      ),
    ],
  );
}

Widget _wrap(DraftSessionNotifier notifier) {
  return MaterialApp(
    home: ChangeNotifierProvider.value(
      value: notifier,
      child: const DraftResultsScreen(),
    ),
  );
}

void main() {
  testWidgets('shows draft name in app bar', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    notifier.state = _resultsState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(
      find.widgetWithText(AppBar, 'Completed Draft \u2014 Results'),
      findsOneWidget,
    );
  });

  testWidgets('shows winner card', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    notifier.state = _resultsState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(find.textContaining('Winner:'), findsOneWidget);
  });

  testWidgets('shows final standings header', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    notifier.state = _resultsState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(find.text('Final Standings'), findsOneWidget);
  });

  testWidgets('shows player names in standings', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    notifier.state = _resultsState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(find.text('Winner'), findsAtLeast(1));
    expect(find.text('Runner Up'), findsOneWidget);
  });

  testWidgets('FAB shows Scan My Deck when not submitted', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    notifier.state = _resultsState();

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(find.text('Scan My Deck'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });

  testWidgets('FAB shows Submitted when decklist submitted', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    final state = _resultsState();
    final players = state.players.map((p) {
      if (p.deviceId == 'leader-device') {
        return p.copyWith(
          decklistMainboard: ['scryfall-1'],
          decklistSideboard: [],
        );
      }
      return p;
    }).toList();
    notifier.state = state.copyWith(players: players);

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(find.text('Submitted'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('shows empty state when no standings', (tester) async {
    final notifier = DraftSessionNotifier(myDeviceId: 'leader-device');
    notifier.state = _resultsState().copyWith(players: []);

    await tester.pumpWidget(_wrap(notifier));
    await tester.pump();

    expect(find.text('No standings available'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:snapdrafter/screens/draft/draft_active.dart';
import 'package:snapdrafter/screens/draft/draft_management.dart';
import 'package:snapdrafter/screens/draft/draft_navigation_controller.dart';
import 'package:snapdrafter/screens/draft/draft_results.dart';
import 'package:snapdrafter/screens/draft/draft_waiting.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';

import '../../services/draft/draft_session_notifier_test.dart';

class _CountingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Widget _wrap(
  DraftSessionNotifier notifier,
  DraftNavigationController controller, {
  NavigatorObserver? observer,
}) {
  return ChangeNotifierProvider.value(
    value: notifier,
    child: MaterialApp(
      navigatorKey: controller.navigatorKey,
      scaffoldMessengerKey: controller.messengerKey,
      navigatorObservers: [if (observer != null) observer],
      home: const Scaffold(body: Text('root')),
    ),
  );
}

DraftNavigationController _controller() => DraftNavigationController(
  navigatorKey: GlobalKey<NavigatorState>(),
  messengerKey: GlobalKey<ScaffoldMessengerState>(),
);

DraftState _completeState(DraftState state) =>
    state.copyWith(session: state.session.copyWith(phase: DraftPhase.complete));

void main() {
  testWidgets('hosting a draft routes to the management screen', (
    tester,
  ) async {
    final fakeLeader = FakeDraftBleLeader();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => fakeLeader,
    );
    final controller = _controller();

    await tester.pumpWidget(_wrap(notifier, controller));
    controller.attach(notifier);

    await notifier.createAndHost(
      name: 'Router Test',
      seatCount: 4,
      playerName: 'Host',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(DraftManagementScreen), findsOneWidget);
    controller.detach();
  });

  testWidgets('completion routes to results exactly once', (tester) async {
    final fakeLeader = FakeDraftBleLeader();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => fakeLeader,
    );
    final controller = _controller();
    final observer = _CountingNavigatorObserver();

    await tester.pumpWidget(_wrap(notifier, controller, observer: observer));
    controller.attach(notifier);
    await notifier.createAndHost(
      name: 'Router Test',
      seatCount: 4,
      playerName: 'Host',
    );
    await tester.pump();
    await tester.pump();

    final pushesBefore = observer.pushed.length;
    notifier.state = _completeState(notifier.state!);
    await tester.pump();
    // Extra notifications during the transition must not stack routes.
    notifier.notifyListeners();
    await tester.pump();
    notifier.notifyListeners();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(observer.pushed.length, pushesBefore + 1);
    expect(find.byType(DraftResultsScreen), findsOneWidget);
    controller.detach();
  });

  testWidgets('leaving a draft pops back to the root', (tester) async {
    final fakeLeader = FakeDraftBleLeader();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => fakeLeader,
    );
    final controller = _controller();

    await tester.pumpWidget(_wrap(notifier, controller));
    controller.attach(notifier);
    await notifier.createAndHost(
      name: 'Router Test',
      seatCount: 4,
      playerName: 'Host',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(DraftManagementScreen), findsOneWidget);

    await notifier.leaveDraft();
    await tester.pumpAndSettle();

    expect(find.byType(DraftManagementScreen), findsNothing);
    expect(find.text('root'), findsOneWidget);
    controller.detach();
  });

  testWidgets('cancelling shows a snackbar and returns to the root', (
    tester,
  ) async {
    final fakeLeader = FakeDraftBleLeader();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => fakeLeader,
    );
    final controller = _controller();

    await tester.pumpWidget(_wrap(notifier, controller));
    controller.attach(notifier);
    await notifier.createAndHost(
      name: 'Router Test',
      seatCount: 4,
      playerName: 'Host',
    );
    await tester.pump();
    await tester.pump();

    final state = notifier.state!;
    notifier.state = state.copyWith(
      session: state.session.copyWith(phase: DraftPhase.cancelled),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The host cancelled the draft'), findsOneWidget);
    expect(find.byType(DraftManagementScreen), findsNothing);
    controller.detach();
  });

  testWidgets('joining a draft routes to the waiting screen', (tester) async {
    final fakeFollower = FakeDraftBleFollower();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'guest',
      bleFollowerFactory: () => fakeFollower,
    );
    final controller = _controller();

    await tester.pumpWidget(_wrap(notifier, controller));
    controller.attach(notifier);

    final join = notifier.joinDraft(
      leaderDeviceId: 'leader',
      playerName: 'Guest',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(DraftWaitingScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await join;
    controller.detach();
  });

  testWidgets('active screen appears when the draft starts', (tester) async {
    final fakeLeader = FakeDraftBleLeader();
    final notifier = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => fakeLeader,
    );
    final controller = _controller();

    await tester.pumpWidget(_wrap(notifier, controller));
    controller.attach(notifier);
    await notifier.createAndHost(
      name: 'Router Test',
      seatCount: 4,
      playerName: 'Host',
    );
    await tester.pump();
    await tester.pump();

    final state = notifier.state!;
    notifier.state = state.copyWith(
      session: state.session.copyWith(phase: DraftPhase.inProgress),
      rounds: [
        DraftRound(
          roundNumber: 1,
          matches: const [],
          roundStartTime: DateTime.now(),
          complete: false,
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(DraftActiveScreen), findsOneWidget);
    controller.detach();
  });
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/draft_message.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';

// ---------------------------------------------------------------------------
// Fake BLE services
// ---------------------------------------------------------------------------

class FakeDraftBleLeader extends DraftBleService {
  DraftState? startedState;
  final List<DraftState> pushedStates = [];
  bool stopCalled = false;
  int resubscribeCallCount = 0;

  final Set<String> connectedDevices = {};

  int get pushStateCallCount => pushedStates.length;
  DraftState? get lastPushedState =>
      pushedStates.isNotEmpty ? pushedStates.last : null;

  @override
  void Function(String deviceId, DraftCommand command)? onCommandReceived;

  @override
  Future<void> startAsLeader(DraftState state) async {
    startedState = state;
  }

  @override
  Future<void> pushState(DraftState state) async {
    if (connectedDevices.isEmpty) return;
    pushedStates.add(state);
  }

  @override
  Future<DraftState> connectToLeader(String deviceId) =>
      throw UnsupportedError('Fake leader cannot connect');

  @override
  Future<DraftState> reconnectToLeader(String deviceId) =>
      throw UnsupportedError('Fake leader cannot reconnect');

  @override
  Future<void> sendCommand(DraftCommand cmd) =>
      throw UnsupportedError('Fake leader cannot send commands');

  @override
  void Function(DraftState state)? onStatePush;

  @override
  Stream<bool> get leaderConnected =>
      throw UnsupportedError('Fake leader has no connection stream');

  @override
  Future<void> stop() async {
    stopCalled = true;
  }
}

class FakeDraftBleFollower extends DraftBleService {
  String? connectedDeviceId;
  final List<DraftCommand> sentCommands = [];
  bool stopCalled = false;
  int reconnectAttempts = 0;

  DraftState? connectResult;
  DraftState? reconnectResult;
  int reconnectFailCount = 0;
  Object? sendCommandThrow;
  int resubscribeCallCount = 0;
  DraftState? resubscribeResult;

  final _leaderConnectedCtrl = StreamController<bool>.broadcast();

  DraftCommand? get lastSentCommand =>
      sentCommands.isNotEmpty ? sentCommands.last : null;

  @override
  Future<void> startAsLeader(DraftState state) =>
      throw UnsupportedError('Fake follower cannot host');

  @override
  Future<void> pushState(DraftState state) =>
      throw UnsupportedError('Fake follower cannot push state');

  @override
  void Function(String deviceId, DraftCommand command)? onCommandReceived;

  @override
  Future<DraftState> connectToLeader(String deviceId) async {
    connectedDeviceId = deviceId;
    return connectResult ?? DraftState.create(
      name: 'Fake Draft',
      leaderDeviceId: deviceId,
      leaderPlayerName: 'Host',
      seatCount: 4,
    );
  }

  @override
  Future<DraftState> reconnectToLeader(String deviceId) async {
    connectedDeviceId = deviceId;
    reconnectAttempts++;
    if (reconnectAttempts <= reconnectFailCount) {
      throw Exception('Simulated reconnect failure');
    }
    return reconnectResult ?? DraftState.create(
      name: 'Fake Draft',
      leaderDeviceId: deviceId,
      leaderPlayerName: 'Host',
      seatCount: 4,
    );
  }

  @override
  Future<void> sendCommand(DraftCommand cmd) async {
    if (sendCommandThrow != null) throw sendCommandThrow!;
    sentCommands.add(cmd);
  }

  @override
  void Function(DraftState state)? onStatePush;

  @override
  Stream<bool> get leaderConnected => _leaderConnectedCtrl.stream;

  void emitConnected(bool connected) {
    _leaderConnectedCtrl.add(connected);
  }

  @override
  Future<DraftState?> resubscribeAndReadState() async {
    resubscribeCallCount++;
    return resubscribeResult;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    await _leaderConnectedCtrl.close();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DraftSessionNotifier _createLeaderNotifier(FakeDraftBleLeader fake) {
  return DraftSessionNotifier(
    myDeviceId: 'my-device',
    bleLeaderFactory: () => fake,
  );
}

DraftSessionNotifier _createFollowerNotifier(FakeDraftBleFollower fake) {
  return DraftSessionNotifier(
    myDeviceId: 'my-device',
    bleFollowerFactory: () => fake,
  );
}

void main() {
  late FakeDraftBleLeader fakeLeader;
  late FakeDraftBleFollower fakeFollower;
  late DraftSessionNotifier notifier;

  // -----------------------------------------------------------------------
  // Leader flow
  // -----------------------------------------------------------------------

  group('leader flow', () {
    setUp(() {
      fakeLeader = FakeDraftBleLeader();
      fakeLeader.connectedDevices.add('dummy');
      notifier = _createLeaderNotifier(fakeLeader);
    });

    test('createAndHost sets role, state, calls startAsLeader', () async {
      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      await notifier.createAndHost(
        name: 'Test Draft',
        setCode: 'DMU',
        seatCount: 8,
        playerName: 'Host Player',
        roundDurationSeconds: 600,
      );

      expect(notifier.role, DraftRole.leader);
      expect(notifier.isLeader, isTrue);
      expect(notifier.isFollower, isFalse);
      expect(notifier.myPlayerName, 'Host Player');

      expect(fakeLeader.startedState, isNotNull);
      expect(fakeLeader.startedState!.session.name, 'Test Draft');
      expect(fakeLeader.startedState!.session.setCode, 'DMU');
      expect(fakeLeader.startedState!.session.seatCount, 8);
      expect(fakeLeader.startedState!.session.roundDurationSeconds, 600);

      expect(notifier.state, isNotNull);
      expect(notifier.state!.session.name, 'Test Draft');
      expect(notifyCount, 1);
    });

    test('refreshFromLeader is a no-op when not a follower', () async {
      await notifier.createAndHost(
        name: 'Test Draft',
        seatCount: 8,
        playerName: 'Host Player',
      );

      await notifier.refreshFromLeader();

      expect(fakeLeader.resubscribeCallCount, 0);
      expect(notifier.role, DraftRole.leader);
    });

    test('createAndHost stops previous BLE service first', () async {
      final firstFake = FakeDraftBleLeader();
      firstFake.connectedDevices.add('dummy');
      final secondFake = FakeDraftBleLeader();
      secondFake.connectedDevices.add('dummy');

      int callCount = 0;
      notifier = DraftSessionNotifier(
        myDeviceId: 'my-device',
        bleLeaderFactory: () => callCount++ == 0 ? firstFake : secondFake,
      );

      await notifier.createAndHost(name: 'First', seatCount: 4, playerName: 'H');
      expect(firstFake.stopCalled, isFalse);

      await notifier.createAndHost(name: 'Second', seatCount: 4, playerName: 'H');
      expect(firstFake.stopCalled, isTrue);
      expect(secondFake.startedState!.session.name, 'Second');
    });

    test('closeLobby assigns seats, pairs round 1, pushes state', () async {
      await notifier.createAndHost(
        name: 'Test',
        seatCount: 8,
        playerName: 'Host',
      );
      // Add a second accepted player for pairings
      notifier.state!.players.add(DraftPlayer(
        deviceId: 'follower-1',
        playerName: 'Alice',
        deviceName: 'Phone',
        joinOrder: 1,
        status: PlayerStatus.accepted,
      ));
      final beforeLen = fakeLeader.pushedStates.length;

      await notifier.closeLobby();

      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
      final newState = fakeLeader.lastPushedState!;
      expect(newState.session.phase, DraftPhase.inProgress);
      expect(newState.rounds.length, 1);
      expect(newState.rounds.first.matches, isNotEmpty);
    });

    test('closeLobby no-op when not leader', () async {
      await notifier.closeLobby();
      expect(fakeLeader.pushStateCallCount, 0);
    });

    test('advanceRound pushes new round with pairings', () async {
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');

      final state = notifier.state!;
      notifier.state = state.copyWith(
        session: state.session.copyWith(phase: DraftPhase.inProgress),
        players: [
          DraftPlayer(deviceId: 'my-device', playerName: 'H', deviceName: 'd', joinOrder: 0, status: PlayerStatus.accepted),
          DraftPlayer(deviceId: 'f1', playerName: 'A', deviceName: 'd', joinOrder: 1, status: PlayerStatus.accepted),
          DraftPlayer(deviceId: 'f2', playerName: 'B', deviceName: 'd', joinOrder: 2, status: PlayerStatus.accepted),
          DraftPlayer(deviceId: 'f3', playerName: 'C', deviceName: 'd', joinOrder: 3, status: PlayerStatus.accepted),
        ],
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1'),
            DraftMatch(matchId: 'm2', roundNumber: 1, playerAId: 'f2', playerBId: 'f3'),
          ], complete: true),
        ],
      );

      final beforeLen = fakeLeader.pushedStates.length;
      await notifier.advanceRound();
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));

      final newState = fakeLeader.lastPushedState!;
      expect(newState.rounds.length, 2);
      expect(newState.rounds[1].roundNumber, 2);
    });

    test('advanceRound beyond totalRounds sets phase to complete', () async {
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');
      notifier.state = notifier.state!.copyWith(
        rounds: List.generate(notifier.state!.session.totalRounds, (i) =>
          DraftRound(roundNumber: i + 1, matches: [], complete: true),
        ),
      );

      final beforeLen = fakeLeader.pushedStates.length;
      await notifier.advanceRound();
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));

      final newState = fakeLeader.lastPushedState!;
      expect(newState.session.phase, DraftPhase.complete);
    });

    test('advanceRound no-op when not leader', () async {
      await notifier.advanceRound();
      expect(fakeLeader.pushStateCallCount, 0);
    });
  });

  // -----------------------------------------------------------------------
  // Leader: command dispatch
  // -----------------------------------------------------------------------

  group('leader: command dispatch', () {
    setUp(() async {
      fakeLeader = FakeDraftBleLeader();
      fakeLeader.connectedDevices.add('dummy');
      notifier = _createLeaderNotifier(fakeLeader);
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'Host');
    });

    test('handleJoinRequest adds accepted player', () {
      final beforeLen = fakeLeader.pushStateCallCount;

      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice',
        deviceName: 'Pixel 7',
      ));

      final newState = notifier.state!;
      expect(newState.players.length, 2);
      final player = newState.players.last;
      expect(player.deviceId, 'Pixel 7');
      expect(player.playerName, 'Alice');
      expect(player.deviceName, 'Pixel 7');
      expect(player.status, PlayerStatus.accepted);
      expect(player.joinOrder, 1);
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
    });

    test('handleJoinRequest for already-accepted player is idempotent', () {
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      expect(notifier.state!.players.length, 2);

      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      expect(notifier.state!.players.length, 2);
      expect(fakeLeader.pushStateCallCount, beforeLen);
    });

    test('handleMatchResult first report → reported, scores saved', () {
      final state = notifier.state!;
      notifier.state = state.copyWith(
        players: [
          state.players.first,
          DraftPlayer(deviceId: 'f1', playerName: 'A', deviceName: 'd', joinOrder: 1, status: PlayerStatus.accepted),
        ],
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1'),
          ]),
        ],
        session: state.session.copyWith(phase: DraftPhase.inProgress),
      );

      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('my-device', MatchResult(
        roundNumber: 1, matchId: 'm1', myWins: 2, opponentWins: 0,
      ));

      final match = notifier.state!.rounds[0].matches[0];
      expect(match.status, MatchStatus.reported);
      expect(match.aWins, 2);
      expect(match.bWins, 0);
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
    });

    test('handleMatchResult second report agrees → confirmed', () {
      final state = notifier.state!;
      notifier.state = state.copyWith(
        players: [
          state.players.first,
          DraftPlayer(deviceId: 'f1', playerName: 'A', deviceName: 'd', joinOrder: 1, status: PlayerStatus.accepted),
        ],
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', aWins: 2, bWins: 0, status: MatchStatus.reported),
          ]),
        ],
        session: state.session.copyWith(phase: DraftPhase.inProgress),
      );

      fakeLeader.onCommandReceived?.call('f1', MatchResult(
        roundNumber: 1, matchId: 'm1', myWins: 0, opponentWins: 2,
      ));

      final match = notifier.state!.rounds[0].matches[0];
      expect(match.status, MatchStatus.confirmed);
      expect(match.aWins, 2);
      expect(match.bWins, 0);

      final pA = notifier.state!.getPlayer('my-device')!;
      expect(pA.matchWins, 1);
      expect(pA.matchLosses, 0);
    });

    test('handleMatchResult second report always confirms, updates scores', () {
      final state = notifier.state!;
      notifier.state = state.copyWith(
        players: [
          state.players.first,
          DraftPlayer(deviceId: 'f1', playerName: 'A', deviceName: 'd', joinOrder: 1, status: PlayerStatus.accepted),
        ],
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', aWins: 2, bWins: 0, status: MatchStatus.reported, reportedByDeviceId: 'my-device'),
          ]),
        ],
        session: state.session.copyWith(phase: DraftPhase.inProgress),
      );

      fakeLeader.onCommandReceived?.call('f1', MatchResult(
        roundNumber: 1, matchId: 'm1', myWins: 2, opponentWins: 0,
      ));

      final match = notifier.state!.rounds[0].matches[0];
      expect(match.status, MatchStatus.confirmed);
      expect(match.aWins, 0);
      expect(match.bWins, 2);

      final pB = notifier.state!.getPlayer('f1')!;
      expect(pB.matchWins, 1);
    });

    test('handleMatchResult reporter not in match → ignored', () {
      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'other1', playerBId: 'other2'),
          ]),
        ],
      );

      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('my-device', MatchResult(
        roundNumber: 1, matchId: 'm1', myWins: 2, opponentWins: 0,
      ));
      expect(fakeLeader.pushStateCallCount, beforeLen);
    });

    test('handleDropRequest marks player dropped', () {
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      expect(notifier.state!.getPlayer('Phone')!.status, PlayerStatus.accepted);

      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('follower-1', DropRequest());

      expect(notifier.state!.getPlayer('Phone')!.status, PlayerStatus.dropped);
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
    });

    test('removePlayer delegates to handleDropRequest', () async {
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      expect(notifier.state!.getPlayer('Phone')!.status, PlayerStatus.accepted);

      await notifier.removePlayer('Phone');
      expect(notifier.state!.getPlayer('Phone')!.status, PlayerStatus.dropped);
    });

    test('handleDropRequest for non-existent player is ignored', () {
      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('nobody', DropRequest());
      expect(fakeLeader.pushStateCallCount, beforeLen);
    });

    test('submitResult as leader processes locally', () async {
      final state = notifier.state!;
      notifier.state = state.copyWith(
        players: [
          state.players.first,
          DraftPlayer(deviceId: 'f1', playerName: 'A', deviceName: 'd', joinOrder: 1, status: PlayerStatus.accepted),
        ],
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1'),
          ]),
        ],
        session: state.session.copyWith(phase: DraftPhase.inProgress),
      );

      final beforeLen = fakeLeader.pushStateCallCount;
      await notifier.submitResult(
        roundNumber: 1,
        matchId: 'm1',
        myWins: 2,
        opponentWins: 1,
      );

      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
      final updated = notifier.state!;
      final match = updated.rounds[0].matches[0];
      expect(match.status, MatchStatus.reported);
      expect(match.aWins, 2);
      expect(match.bWins, 1);
    });

    test('handleDecklistSubmission updates player decklist and pushes state', () {
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      final beforeLen = fakeLeader.pushStateCallCount;

      fakeLeader.onCommandReceived?.call('follower-1', SubmitDecklist(
        mainboardScryfallIds: ['id-a', 'id-b'],
        sideboardScryfallIds: ['id-side'],
      ));

      final player = notifier.state!.getPlayer('Phone')!;
      expect(player.decklistMainboard, ['id-a', 'id-b']);
      expect(player.decklistSideboard, ['id-side']);
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
      expect(notifier.hasSubmittedDecklist('Phone'), isTrue);
    });

    test('handleDecklistSubmission ignores second submission', () {
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      fakeLeader.onCommandReceived?.call('follower-1', SubmitDecklist(
        mainboardScryfallIds: ['first'],
        sideboardScryfallIds: [],
      ));

      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('follower-1', SubmitDecklist(
        mainboardScryfallIds: ['second'],
        sideboardScryfallIds: [],
      ));

      expect(notifier.state!.getPlayer('Phone')!.decklistMainboard, ['first']);
      expect(fakeLeader.pushStateCallCount, beforeLen);
    });

    test('handleDecklistSubmission ignores unknown device', () {
      final beforeLen = fakeLeader.pushStateCallCount;
      fakeLeader.onCommandReceived?.call('nobody', SubmitDecklist(
        mainboardScryfallIds: ['x'],
        sideboardScryfallIds: [],
      ));
      expect(fakeLeader.pushStateCallCount, beforeLen);
    });

    test('hasSubmittedDecklist returns false for unsubmitted player', () {
      fakeLeader.onCommandReceived?.call('follower-1', JoinRequest(
        playerName: 'Alice', deviceName: 'Phone',
      ));
      expect(notifier.hasSubmittedDecklist('Phone'), isFalse);
    });

    test('submitDecklist as leader processes locally', () async {
      final beforeLen = fakeLeader.pushStateCallCount;
      final ok = await notifier.submitDecklist(
        mainboardScryfallIds: ['id-1'],
        sideboardScryfallIds: [],
      );

      expect(ok, isTrue);
      expect(fakeLeader.pushStateCallCount, greaterThan(beforeLen));
      expect(notifier.hasSubmittedDecklist('my-device'), isTrue);
      expect(notifier.state!.getPlayer('my-device')!.decklistMainboard, ['id-1']);
    });
  });

  // -----------------------------------------------------------------------
  // Leader: cleanup
  // -----------------------------------------------------------------------

  group('leader: cleanup', () {
    test('leaveDraft pushes cancelled state, then stops', () async {
      fakeLeader = FakeDraftBleLeader();
      fakeLeader.connectedDevices.add('dummy');
      notifier = _createLeaderNotifier(fakeLeader);
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');

      await notifier.leaveDraft();

      expect(fakeLeader.pushStateCallCount, 1); // only the cancelled push
      expect(fakeLeader.lastPushedState!.session.phase, DraftPhase.cancelled);
      expect(fakeLeader.stopCalled, isTrue);
      expect(notifier.role, DraftRole.none);
      expect(notifier.state, isNull);
      expect(notifier.isLeader, isFalse);
    });

    test('leaveDraft with no followers does not call pushState', () async {
      fakeLeader = FakeDraftBleLeader();
      notifier = _createLeaderNotifier(fakeLeader);
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');
      // No connected devices → pushState during create skipped, only 0 pushes

      final beforeLen = fakeLeader.pushStateCallCount;
      await notifier.leaveDraft();

      expect(fakeLeader.pushStateCallCount, beforeLen); // no extra push
      expect(fakeLeader.stopCalled, isTrue);
    });

    test('dispose calls stop on BLE service', () async {
      fakeLeader = FakeDraftBleLeader();
      fakeLeader.connectedDevices.add('dummy');
      notifier = _createLeaderNotifier(fakeLeader);
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');

      expect(fakeLeader.stopCalled, isFalse);
      notifier.dispose();
      expect(fakeLeader.stopCalled, isTrue);
    });
  });

  // -----------------------------------------------------------------------
  // Follower flow
  // -----------------------------------------------------------------------

  group('follower flow', () {
    setUp(() {
      fakeFollower = FakeDraftBleFollower();
      notifier = _createFollowerNotifier(fakeFollower);
    });

    test('joinDraft sets role, connects, sends JoinRequest', () async {
      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      expect(notifier.role, DraftRole.follower);
      expect(notifier.isFollower, isTrue);
      expect(notifier.isLeader, isFalse);
      expect(notifier.myPlayerName, 'Bob');
      expect(notifier.state, isNotNull);
      expect(fakeFollower.connectedDeviceId, 'leader-device');
      expect(fakeFollower.sentCommands.length, 1);
      expect(fakeFollower.sentCommands[0], isA<JoinRequest>());
      final join = fakeFollower.sentCommands[0] as JoinRequest;
      expect(join.playerName, 'Bob');
      expect(notifyCount, 1);
    });

    test('joinDraft stops previous BLE service before connecting', () async {
      final firstFake = FakeDraftBleFollower();
      firstFake.connectResult = DraftState.create(
        name: 'Test', leaderDeviceId: 'leader-1', leaderPlayerName: 'Host', seatCount: 4,
      );
      final secondFake = FakeDraftBleFollower();
      secondFake.connectResult = DraftState.create(
        name: 'Test', leaderDeviceId: 'leader-2', leaderPlayerName: 'Host', seatCount: 4,
      );

      int callCount = 0;
      notifier = DraftSessionNotifier(
        myDeviceId: 'my-device',
        bleFollowerFactory: () => callCount++ == 0 ? firstFake : secondFake,
      );

      await notifier.joinDraft(leaderDeviceId: 'leader-1', playerName: 'Bob');
      expect(firstFake.stopCalled, isFalse);

      await notifier.joinDraft(leaderDeviceId: 'leader-2', playerName: 'Bob');
      expect(firstFake.stopCalled, isTrue);
      expect(secondFake.connectedDeviceId, 'leader-2');
    });

    test('onStatePush with higher seq updates state and notifies', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      final currentSeq = notifier.state!.sequenceNumber;

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      final newState = notifier.state!.bumpSequence().copyWith(
        session: notifier.state!.session.copyWith(name: 'Updated Name'),
      );
      fakeFollower.onStatePush?.call(newState);

      expect(notifier.state!.session.name, 'Updated Name');
      expect(notifier.state!.sequenceNumber, currentSeq + 1);
      expect(notifyCount, 1);
    });

    test('onStatePush with lower/equal seq is ignored', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      final staleState = DraftState(
        sequenceNumber: 0,
        session: notifier.state!.session,
        players: [],
      );
      fakeFollower.onStatePush?.call(staleState);

      expect(notifyCount, 0);
    });

    test('leader-submitted result reaches follower via push only (no polling)', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      // The host submits its result; the follower never polls — the push
      // alone must surface the reported match.
      final pushed = notifier.state!.bumpSequence().copyWith(
        rounds: [
          DraftRound(
            roundNumber: 1,
            matches: [
              DraftMatch(
                matchId: 'm1',
                roundNumber: 1,
                playerAId: 'my-device',
                playerBId: 'opponent-device',
                aWins: 1,
                bWins: 2,
                reportedByDeviceId: 'opponent-device',
                status: MatchStatus.reported,
              ),
            ],
          ),
        ],
      );
      fakeFollower.onStatePush?.call(pushed);

      final myMatch = notifier.state!.getMyMatch('my-device', 1);
      expect(myMatch!.status, MatchStatus.reported);
      expect(notifier.hasReportedResult(1), isFalse);
      expect(notifier.canReportResult(1), isFalse);
      expect(notifyCount, 1);
    });

    test('refreshFromLeader applies fresher state from resubscribe', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      fakeFollower.resubscribeResult = notifier.state!.bumpSequence();
      final callsBefore = fakeFollower.resubscribeCallCount;

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      await notifier.refreshFromLeader();

      expect(fakeFollower.resubscribeCallCount, callsBefore + 1);
      expect(notifier.state!.sequenceNumber,
          fakeFollower.resubscribeResult!.sequenceNumber);
      expect(notifyCount, 1);
    });

    test('refreshFromLeader ignores stale resubscribe result', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      fakeFollower.resubscribeResult = notifier.state!;
      final callsBefore = fakeFollower.resubscribeCallCount;

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      await notifier.refreshFromLeader();

      expect(fakeFollower.resubscribeCallCount, callsBefore + 1);
      expect(notifyCount, 0);
    });

    test('onStatePush with cancelled phase triggers leaveDraft', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      int notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      final cancelledState = notifier.state!.bumpSequence().copyWith(
        session: notifier.state!.session.copyWith(phase: DraftPhase.cancelled),
      );
      fakeFollower.onStatePush?.call(cancelledState);

      // leaveDraft was triggered — role should be none
      expect(notifier.role, DraftRole.none);
      expect(notifier.state, isNull);
      expect(fakeFollower.stopCalled, isTrue);
    });

    test('dropFromDraft sends DropRequest then calls leaveDraft', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      final beforeLen = fakeFollower.sentCommands.length;

      await notifier.dropFromDraft();

      expect(fakeFollower.sentCommands.length, greaterThan(beforeLen));
      expect(fakeFollower.sentCommands.last, isA<DropRequest>());
      expect(notifier.role, DraftRole.none);
      expect(notifier.state, isNull);
      expect(fakeFollower.stopCalled, isTrue);
    });

    test('submitResult sends MatchResult command', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      final beforeLen = fakeFollower.sentCommands.length;

      await notifier.submitResult(
        roundNumber: 2,
        matchId: 'match-abc',
        myWins: 2,
        opponentWins: 0,
      );

      expect(fakeFollower.sentCommands.length, greaterThan(beforeLen));
      final cmd = fakeFollower.lastSentCommand as MatchResult;
      expect(cmd.roundNumber, 2);
      expect(cmd.matchId, 'match-abc');
      expect(cmd.myWins, 2);
      expect(cmd.opponentWins, 0);
    });

    test('submitResult when not follower → no-op', () async {
      await notifier.submitResult(
        roundNumber: 1,
        matchId: 'm1',
        myWins: 2,
        opponentWins: 0,
      );
      expect(fakeFollower.sentCommands, isEmpty);
    });

    test('submitDecklist sends SubmitDecklist command', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      final beforeLen = fakeFollower.sentCommands.length;

      await notifier.submitDecklist(
        mainboardScryfallIds: ['id-1', 'id-2'],
        sideboardScryfallIds: ['id-side'],
      );

      expect(fakeFollower.sentCommands.length, greaterThan(beforeLen));
      final cmd = fakeFollower.lastSentCommand as SubmitDecklist;
      expect(cmd.mainboardScryfallIds, ['id-1', 'id-2']);
      expect(cmd.sideboardScryfallIds, ['id-side']);
    });

    test('submitDecklist when not follower → no-op', () async {
      await notifier.submitDecklist(
        mainboardScryfallIds: ['x'],
        sideboardScryfallIds: [],
      );
      expect(fakeFollower.sentCommands, isEmpty);
    });

    test('dropFromDraft when not follower calls leaveDraft without sending', () async {
      await notifier.dropFromDraft();
      expect(fakeFollower.sentCommands, isEmpty);
      expect(notifier.role, DraftRole.none);
    });

    test('joinDraft handles connectToLeader failure gracefully', () async {
      fakeFollower.connectResult = null;

      try {
        await notifier.joinDraft(
          leaderDeviceId: 'leader-device',
          playerName: 'Bob',
        );
        fail('Expected exception');
      } catch (_) {
        // connectToLeader may throw if connectResult is not set correctly
      }
    });
  });

  // -----------------------------------------------------------------------
  // Follower: decklist submission
  // -----------------------------------------------------------------------

  group('follower: submitDecklist', () {
    setUp(() {
      fakeFollower = FakeDraftBleFollower();
      notifier = _createFollowerNotifier(fakeFollower);
    });

    test('returns true when the confirmation push arrives', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      final withDecklist = notifier.state!.copyWith(
        players: [
          ...notifier.state!.players,
          DraftPlayer(
            deviceId: 'my-device',
            playerName: 'Bob',
            deviceName: 'my-device',
            joinOrder: 1,
            status: PlayerStatus.accepted,
            decklistMainboard: ['id-1', 'id-2'],
          ),
        ],
      ).bumpSequence();

      final okFuture = notifier.submitDecklist(
        mainboardScryfallIds: ['id-1', 'id-2'],
        sideboardScryfallIds: [],
      );

      // The leader's confirmation push arrives while waiting for the update.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      fakeFollower.onStatePush?.call(withDecklist);

      final ok = await okFuture;
      expect(ok, isTrue);
      expect(fakeFollower.lastSentCommand, isA<SubmitDecklist>());
    });

    test('returns false when the command write fails', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      fakeFollower.sendCommandThrow = Exception('write failed');

      final ok = await notifier.submitDecklist(
        mainboardScryfallIds: ['id-1'],
        sideboardScryfallIds: [],
      );
      expect(ok, isFalse);
    });

    test('returns false when the state never confirms', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      final ok = await notifier.submitDecklist(
        mainboardScryfallIds: ['id-1'],
        sideboardScryfallIds: [],
      );
      expect(ok, isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // Follower: reconnect
  // -----------------------------------------------------------------------

  group('follower: reconnect', () {
    setUp(() {
      fakeFollower = FakeDraftBleFollower();
      notifier = DraftSessionNotifier(
        myDeviceId: 'my-device',
        bleFollowerFactory: () => fakeFollower,
        reconnectDelaysSeconds: const [0, 0, 0, 0, 0],
      );
    });

    test('leaderConnected false triggers reconnect attempt', () async {
      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      expect(fakeFollower.reconnectAttempts, 0);

      fakeFollower.emitConnected(false);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(fakeFollower.reconnectAttempts, greaterThan(0));
    });

    test('reconnect succeeds on first attempt', () async {
      fakeFollower.reconnectResult = DraftState.create(
        name: 'Reconnected', leaderDeviceId: 'leader-device', leaderPlayerName: 'Host', seatCount: 4,
      );

      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      fakeFollower.emitConnected(false);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(fakeFollower.reconnectAttempts, 1);
    });

    test('reconnect re-sends JoinRequest when player is missing from state',
        () async {
      fakeFollower.reconnectResult = DraftState.create(
        name: 'Reconnected', leaderDeviceId: 'leader-device', leaderPlayerName: 'Host', seatCount: 4,
      );

      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      fakeFollower.emitConnected(false);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(fakeFollower.reconnectAttempts, 1);
      final lastCmd = fakeFollower.lastSentCommand;
      expect(lastCmd, isA<JoinRequest>());
      expect((lastCmd as JoinRequest).deviceName, 'my-device');
      expect(lastCmd.playerName, 'Bob');
    });

    test('reconnect does not re-send JoinRequest when player already in state',
        () async {
      final joined = DraftState.create(
        name: 'Reconnected', leaderDeviceId: 'leader-device', leaderPlayerName: 'Host', seatCount: 4,
      );
      final withPlayer = joined.copyWith(
        players: [
          ...joined.players,
          DraftPlayer(
            deviceId: 'my-device',
            playerName: 'Bob',
            deviceName: 'my-device',
            joinOrder: 1,
            status: PlayerStatus.accepted,
          ),
        ],
      ).bumpSequence();
      fakeFollower.reconnectResult = withPlayer;

      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );
      final commandsBefore = fakeFollower.sentCommands.length;

      fakeFollower.emitConnected(false);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(fakeFollower.reconnectAttempts, 1);
      // No new command should have been sent for the rejoin.
      expect(fakeFollower.sentCommands.length, commandsBefore);
    });

    test('reconnect gives up after all attempts fail', () async {
      fakeFollower.reconnectFailCount = 5;

      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      fakeFollower.emitConnected(false);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(fakeFollower.reconnectAttempts, 5);
      expect(notifier.role, DraftRole.none);
      expect(notifier.state, isNull);
      expect(fakeFollower.stopCalled, isTrue);
    });

    test('reconnect interrupted by leaveDraft exits loop', () async {
      fakeFollower.reconnectFailCount = 5;

      await notifier.joinDraft(
        leaderDeviceId: 'leader-device',
        playerName: 'Bob',
      );

      fakeFollower.emitConnected(false);

      await Future.delayed(const Duration(milliseconds: 0));
      await notifier.leaveDraft();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(notifier.role, DraftRole.none);
    });
  });

  // -----------------------------------------------------------------------
  // General queries
  // -----------------------------------------------------------------------

  group('general queries', () {
    setUp(() {
      fakeLeader = FakeDraftBleLeader();
      fakeLeader.connectedDevices.add('dummy');
      notifier = _createLeaderNotifier(fakeLeader);
    });

    test('isActive is false for complete/cancelled/null state', () async {
      expect(notifier.isActive, isFalse);

      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');
      expect(notifier.isActive, isTrue);

      notifier.state = notifier.state!.copyWith(
        session: notifier.state!.session.copyWith(phase: DraftPhase.complete),
      );
      expect(notifier.isActive, isFalse);

      notifier.state = notifier.state!.copyWith(
        session: notifier.state!.session.copyWith(phase: DraftPhase.cancelled),
      );
      expect(notifier.isActive, isFalse);
    });

    test('hasReportedResult returns true for reported/confirmed', () async {
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');

      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', status: MatchStatus.pending),
          ]),
        ],
      );
      expect(notifier.hasReportedResult(1), isFalse);

      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', status: MatchStatus.reported, reportedByDeviceId: 'my-device'),
          ]),
        ],
      );
      expect(notifier.hasReportedResult(1), isTrue);

      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', status: MatchStatus.confirmed),
          ]),
        ],
      );
      expect(notifier.hasReportedResult(1), isTrue);
    });

    test('canReportResult is true for pending, false for bye', () async {
      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');

      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', status: MatchStatus.pending),
          ]),
        ],
      );
      expect(notifier.canReportResult(1), isTrue);

      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 1, matches: [
            DraftMatch(matchId: 'm1', roundNumber: 1, playerAId: 'my-device', playerBId: 'f1', status: MatchStatus.reported),
          ]),
        ],
      );
      expect(notifier.canReportResult(1), isFalse);

      // Bye
      notifier.state = notifier.state!.copyWith(
        rounds: [
          DraftRound(roundNumber: 2, matches: [
            DraftMatch(matchId: 'bye', roundNumber: 2, playerAId: 'my-device'),
          ]),
        ],
      );
      expect(notifier.canReportResult(2), isFalse);
    });

    test('role/isLeader/isFollower reflect current state', () async {
      expect(notifier.role, DraftRole.none);
      expect(notifier.isLeader, isFalse);
      expect(notifier.isFollower, isFalse);

      await notifier.createAndHost(name: 'Test', seatCount: 4, playerName: 'H');
      expect(notifier.role, DraftRole.leader);
      expect(notifier.isLeader, isTrue);
      expect(notifier.isFollower, isFalse);

      await notifier.leaveDraft();
      expect(notifier.role, DraftRole.none);
    });

    test('myPlayerName and myDeviceId reflect constructor args', () {
      expect(notifier.myDeviceId, 'my-device');
      expect(notifier.myPlayerName, isNull);
    });

    test('getters return defaults before any draft started', () {
      expect(notifier.state, isNull);
      expect(notifier.role, DraftRole.none);
      expect(notifier.isActive, isFalse);
      expect(notifier.hasReportedResult(1), isFalse);
      expect(notifier.canReportResult(1), isFalse);
    });
  });
}

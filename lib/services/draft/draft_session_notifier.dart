import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'draft_state.dart';
import 'draft_message.dart';
import 'draft_ble_service.dart';
import 'draft_ble_leader.dart';
import 'draft_ble_follower.dart';
import 'swiss_pairing.dart';
import 'notification_service.dart';

enum DraftRole { none, leader, follower }

/// Top-level coordinator for a draft session.
///
/// Acts as a [ChangeNotifier] so the UI can listen for state updates.
/// Internally delegates BLE work to [DraftBleLeader] or [DraftBleFollower]
/// depending on whether this device is hosting or joining.
///
/// All state mutations happen on the leader; followers receive push
/// notifications of the updated [DraftState] over BLE.
class DraftSessionNotifier extends ChangeNotifier {
  DraftBleService? _bleService;
  DraftState? _state;
  DraftRole _role = DraftRole.none;
  final String _myDeviceId;
  String? _myPlayerName;
  bool _isReconnecting = false;
  StreamSubscription<bool>? _leaderConnectedSub;
  final Map<String, String> _bleToAppId = {};
  final DraftBleService Function()? _bleLeaderFactory;
  final DraftBleService Function()? _bleFollowerFactory;
  final List<int> _reconnectDelaysSeconds;

  DraftSessionNotifier({
    required String myDeviceId,
    DraftBleService Function()? bleLeaderFactory,
    DraftBleService Function()? bleFollowerFactory,
    List<int>? reconnectDelaysSeconds,
  }) : _myDeviceId = myDeviceId,
       _bleLeaderFactory = bleLeaderFactory,
       _bleFollowerFactory = bleFollowerFactory,
       _reconnectDelaysSeconds =
           reconnectDelaysSeconds ?? _defaultReconnectDelays();

  static List<int> _defaultReconnectDelays() {
    // 2s, 5s, 10s, 20s, then 30s repeated to fill ~10 minutes (607 s total)
    return const [
      2,
      5,
      10,
      20,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
      30,
    ];
  }

  // -------------------------------------------------------------------------
  // Getters
  // -------------------------------------------------------------------------

  DraftState? get state => _state;

  /// Test-only setter for injecting a specific state scenario.
  @visibleForTesting
  set state(DraftState? value) {
    _state = value;
    notifyListeners();
  }

  DraftRole get role => _role;
  bool get isLeader => _role == DraftRole.leader;
  bool get isFollower => _role == DraftRole.follower;
  bool get isActive =>
      _state != null &&
      _state!.session.phase != DraftPhase.complete &&
      _state!.session.phase != DraftPhase.cancelled;
  String? get myPlayerName => _myPlayerName;
  String get myDeviceId => _myDeviceId;
  bool get isReconnecting => _isReconnecting;

  bool hasReportedResult(int roundNumber) {
    if (_state == null) return false;
    final myMatch = _state!.getMyMatch(_myDeviceId, roundNumber);
    if (myMatch == null) return false;
    return myMatch.status == MatchStatus.confirmed ||
        myMatch.reportedByDeviceId == _myDeviceId;
  }

  bool canReportResult(int roundNumber) {
    if (_state == null) return false;
    final myMatch = _state!.getMyMatch(_myDeviceId, roundNumber);
    if (myMatch == null) return false;
    if (myMatch.isBye) return false;
    return myMatch.status == MatchStatus.pending;
  }

  // -------------------------------------------------------------------------
  // Leader: lobby creation & management
  // -------------------------------------------------------------------------

  /// Creates a new draft session on this device and starts BLE advertising
  /// so followers can discover and join.
  Future<void> createAndHost({
    required String name,
    String? setCode,
    String? cubeId,
    required int seatCount,
    required String playerName,
    int roundDurationSeconds = 300,
  }) async {
    await _bleService?.stop();
    _myPlayerName = playerName;

    final state = DraftState.create(
      name: name,
      leaderDeviceId: _myDeviceId,
      leaderPlayerName: playerName,
      setCode: setCode,
      cubeId: cubeId,
      seatCount: seatCount,
      roundDurationSeconds: roundDurationSeconds,
    );

    final leader = _bleLeaderFactory?.call() ?? DraftBleLeader();
    leader.onCommandReceived = _handleCommand;
    await leader.startAsLeader(state);

    _bleService = leader;
    _role = DraftRole.leader;
    _state = state;

    leader.followerConnected?.listen((_) {
      if (isLeader &&
          _bleService!.connectedDeviceCount + 1 >= _state!.session.seatCount) {
        _bleService!.pauseAdvertising();
      }
    });

    leader.followerDisconnected?.listen((_) {
      if (_role == DraftRole.leader && _state != null && isActive) {
        leader.resumeAdvertising();
      }
    });

    if (leader.connectedDeviceCount + 1 >= seatCount) {
      leader.pauseAdvertising();
    }

    notifyListeners();
  }

  /// Closes the lobby: randomly shuffles accepted players into seats,
  /// generates round-1 Swiss pairings, and transitions the phase to
  /// [DraftPhase.inProgress].
  Future<void> closeLobby() async {
    if (!isLeader || _state == null) return;

    final acceptedPlayers = _state!.players
        .where((p) => p.status == PlayerStatus.accepted)
        .toList();

    // Randomly assign seat numbers to accepted players.
    final shuffled = [...acceptedPlayers]..shuffle(Random());
    final seated = <DraftPlayer>[];
    for (var i = 0; i < shuffled.length; i++) {
      seated.add(shuffled[i].copyWith(seatNumber: i + 1));
    }

    final remaining = _state!.players
        .where((p) => p.status != PlayerStatus.accepted)
        .toList();

    // Pair round 1 using Swiss pairings.
    final pairer = SwissPairing();
    final round1Matches = pairer.pairRound(1, seated, []);
    final allComplete = round1Matches.every(
      (m) => m.status != MatchStatus.pending || m.isBye,
    );
    final round1 = DraftRound(
      roundNumber: 1,
      matches: round1Matches,
      roundStartTime: DateTime.now(),
      complete: allComplete,
    );

    _state = _state!
        .copyWith(
          players: [...seated, ...remaining],
          rounds: [round1],
          session: _state!.session.copyWith(phase: DraftPhase.inProgress),
        )
        .bumpSequence();

    await _bleService!.pushState(_state!);
    notifyListeners();

    if (_state!.rounds.isNotEmpty) {
      _notifyNewRoundForDevice(_state!.rounds.last, _myDeviceId);
    }
  }

  /// Generates the next round's Swiss pairings and broadcasts them.
  /// If all rounds are complete, marks the session as [DraftPhase.complete].
  Future<void> advanceRound() async {
    if (!isLeader || _state == null) return;

    if (_state!.rounds.isNotEmpty) {
      _finalizeReportedMatches(_state!.rounds.last);
    }

    final nextRoundNumber = _state!.rounds.length + 1;
    if (nextRoundNumber > _state!.session.totalRounds) {
      _state = _state!
          .copyWith(
            session: _state!.session.copyWith(phase: DraftPhase.complete),
          )
          .bumpSequence();
      await _bleService!.pushState(_state!);
      notifyListeners();
      return;
    }

    final acceptedPlayers = _state!.acceptedPlayers;
    final pairer = SwissPairing();
    final matches = pairer.pairRound(
      nextRoundNumber,
      acceptedPlayers,
      _state!.rounds,
    );
    final allComplete = matches.every(
      (m) => m.status != MatchStatus.pending || m.isBye,
    );
    final round = DraftRound(
      roundNumber: nextRoundNumber,
      matches: matches,
      roundStartTime: DateTime.now(),
      complete: allComplete,
    );

    _state = _state!
        .copyWith(rounds: [..._state!.rounds, round])
        .bumpSequence();

    await _bleService!.pushState(_state!);
    notifyListeners();

    _notifyNewRoundForDevice(round, _myDeviceId);
  }

  // -------------------------------------------------------------------------
  // Leader: incoming command dispatch
  // -------------------------------------------------------------------------

  void _handleCommand(String deviceId, DraftCommand cmd) {
    if (!isLeader || _state == null) return;

    switch (cmd) {
      case JoinRequest(:final playerName, :final deviceName):
        _handleJoinRequest(deviceId, playerName, deviceName);
      case MatchResult result:
        _handleMatchResult(_bleToAppId[deviceId] ?? deviceId, result);
      case DropRequest():
        _handleDropRequest(_bleToAppId[deviceId] ?? deviceId);
      case SubmitDecklist cmd:
        _handleDecklistSubmission(_bleToAppId[deviceId] ?? deviceId, cmd);
    }
  }

  /// Adds a joining player to the session. If the player already exists and
  /// is accepted the request is silently ignored (idempotent reconnect).
  void _handleJoinRequest(
    String deviceId,
    String playerName,
    String deviceName,
  ) {
    _log('[NOTIFIER] _handleJoinRequest: $playerName ($deviceId)');
    final existing = _state!.getPlayer(deviceName);
    if (existing != null && existing.status == PlayerStatus.accepted) {
      _log('[NOTIFIER] _handleJoinRequest: player already accepted, ignoring');
      return;
    }

    final joinOrder =
        _state!.players
            .map((p) => p.joinOrder)
            .fold<int>(0, (max, o) => o > max ? o : max) +
        1;

    _bleToAppId[deviceId] = deviceName;

    final newPlayer = DraftPlayer(
      deviceId: deviceName,
      playerName: playerName,
      joinOrder: joinOrder,
      status: PlayerStatus.accepted,
    );

    _state = _state!
        .copyWith(players: [..._state!.players, newPlayer])
        .bumpSequence();

    _bleService!.pushState(_state!);
    notifyListeners();

    if (_bleService!.connectedDeviceCount + 1 >= _state!.session.seatCount) {
      _bleService!.pauseAdvertising();
    }

    _log(
      '[NOTIFIER] _handleJoinRequest done: players=${_state!.players.length}, seq=${_state!.sequenceNumber}',
    );
  }

  // -------------------------------------------------------------------------
  // Leader: match result reporting
  // -------------------------------------------------------------------------

  /// Processes a [MatchResult] command from a follower.
  ///
  /// The first report sets the match to [MatchStatus.reported] and records
  /// the submitter's device ID. The second reporter's submission always
  /// results in [MatchStatus.confirmed]; if their scores differ from the
  /// first report the match scores are updated to the second reporter's values.
  void _handleMatchResult(String reporterId, MatchResult result) {
    final matchIndex = _state!.rounds
        .firstWhere((r) => r.roundNumber == result.roundNumber)
        .matches
        .indexWhere((m) => m.matchId == result.matchId);

    if (matchIndex == -1) return;

    final match = _state!.rounds
        .firstWhere((r) => r.roundNumber == result.roundNumber)
        .matches[matchIndex];

    final isPlayerA = match.playerAId == reporterId;
    final isPlayerB = match.playerBId == reporterId;
    if (!isPlayerA && !isPlayerB) return;

    int? newAWins;
    int? newBWins;

    if (isPlayerA) {
      newAWins = result.myWins;
      newBWins = result.opponentWins;
    } else {
      newBWins = result.myWins;
      newAWins = result.opponentWins;
    }

    switch (match.status) {
      case MatchStatus.confirmed:
        return;

      case MatchStatus.pending:
        final updated = match.copyWith(
          aWins: newAWins,
          bWins: newBWins,
          reportedByDeviceId: reporterId,
          status: MatchStatus.reported,
        );
        _updateMatch(result.roundNumber, matchIndex, updated);

        _notifyMatchResultSubmitted(reporterId, updated);

      case MatchStatus.reported:
        if (match.reportedByDeviceId == reporterId) return;
        final updated = match.copyWith(
          aWins: newAWins,
          bWins: newBWins,
          status: MatchStatus.confirmed,
        );
        _updateMatch(result.roundNumber, matchIndex, updated);
        _updatePlayerRecords(updated, result.roundNumber);
    }
  }

  /// Replaces a single match within its round. If every match in the round
  /// is now complete (or a bye), the round is marked complete.
  void _updateMatch(int roundNumber, int matchIndex, DraftMatch updatedMatch) {
    final rounds = _state!.rounds.toList();
    final roundIndex = rounds.indexWhere((r) => r.roundNumber == roundNumber);
    if (roundIndex == -1) return;

    final matches = rounds[roundIndex].matches.toList();
    matches[matchIndex] = updatedMatch;

    final allComplete = matches.every(
      (m) => m.status != MatchStatus.pending || m.isBye,
    );

    rounds[roundIndex] = rounds[roundIndex].copyWith(
      matches: matches,
      complete: allComplete,
    );

    _state = _state!.copyWith(rounds: rounds).bumpSequence();
    _bleService!.pushState(_state!);
    notifyListeners();
  }

  /// Updates each player's match win/loss/draw totals after a confirmed
  /// match result.
  void _updatePlayerRecords(DraftMatch match, int roundNumber) {
    if (match.playerBId == null) return;

    final players = _state!.players.toList();
    final aIndex = players.indexWhere((p) => p.deviceId == match.playerAId);
    final bIndex = players.indexWhere((p) => p.deviceId == match.playerBId);

    if (aIndex != -1 && match.aWins != null && match.bWins != null) {
      final aWon = match.aWins! > match.bWins!;
      final bWon = match.bWins! > match.aWins!;
      final isDraw = match.aWins == match.bWins;

      players[aIndex] = players[aIndex].copyWith(
        matchWins: players[aIndex].matchWins + (aWon ? 1 : 0),
        matchLosses: players[aIndex].matchLosses + (bWon ? 1 : 0),
        matchDraws: players[aIndex].matchDraws + (isDraw ? 1 : 0),
      );

      players[bIndex] = players[bIndex].copyWith(
        matchWins: players[bIndex].matchWins + (bWon ? 1 : 0),
        matchLosses: players[bIndex].matchLosses + (aWon ? 1 : 0),
        matchDraws: players[bIndex].matchDraws + (isDraw ? 1 : 0),
      );
    }

    _state = _state!.copyWith(players: players).bumpSequence();
    _bleService!.pushState(_state!);
    notifyListeners();
  }

  void _finalizeReportedMatches(DraftRound round) {
    for (int i = 0; i < round.matches.length; i++) {
      final match = round.matches[i];
      if (match.status == MatchStatus.reported) {
        final confirmed = match.copyWith(status: MatchStatus.confirmed);
        _updateMatch(round.roundNumber, i, confirmed);
        _updatePlayerRecords(confirmed, round.roundNumber);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Leader: drop handling
  // -------------------------------------------------------------------------

  void _handleDropRequest(String deviceId) {
    final playerIndex = _state!.players.indexWhere(
      (p) => p.deviceId == deviceId,
    );
    if (playerIndex == -1) return;

    final updatedPlayers = _state!.players.toList();
    updatedPlayers[playerIndex] = updatedPlayers[playerIndex].copyWith(
      status: PlayerStatus.dropped,
    );

    _state = _state!.copyWith(players: updatedPlayers).bumpSequence();
    _bleService!.pushState(_state!);
    notifyListeners();

    Timer(const Duration(seconds: 5), () {
      if (_state == null) return;
      final filtered = _state!.players
          .where((p) => p.deviceId != deviceId)
          .toList();
      if (filtered.length == _state!.players.length) return;
      _state = _state!.copyWith(players: filtered).bumpSequence();
      _bleService?.pushState(_state!);
      notifyListeners();
    });
  }

  /// Processes a [SubmitDecklist] command from a follower or the leader
  /// themselves. Updates the player's decklist in state and pushes the
  /// updated state to all followers. Decklists are immutable after
  /// submission — subsequent submissions from the same player are ignored.
  void _handleDecklistSubmission(String deviceId, SubmitDecklist cmd) {
    if (!isLeader || _state == null) return;

    final players = _state!.players.toList();
    final idx = players.indexWhere((p) => p.deviceId == deviceId);
    if (idx == -1) return;

    if (players[idx].decklistMainboard != null) return;

    players[idx] = players[idx].copyWith(
      decklistMainboard: cmd.mainboardScryfallIds,
      decklistSideboard: cmd.sideboardScryfallIds,
    );

    _state = _state!.copyWith(players: players).bumpSequence();
    _bleService!.pushState(_state!);
    notifyListeners();
  }

  bool hasSubmittedDecklist(String deviceId) {
    return _state?.getPlayer(deviceId)?.decklistMainboard != null;
  }

  // -------------------------------------------------------------------------
  // Follower: joining & submitting
  // -------------------------------------------------------------------------

  /// Connects to the leader's BLE peripheral, subscribes to state
  /// notifications, and sends a [JoinRequest].
  Future<void> joinDraft({
    required String leaderDeviceId,
    required String playerName,
  }) async {
    await _bleService?.stop();
    _myPlayerName = playerName;

    final follower = _bleFollowerFactory?.call() ?? DraftBleFollower();
    follower.onStatePush = (newState) {
      final myPlayer = newState.getPlayer(_myDeviceId);
      if (myPlayer != null && myPlayer.status == PlayerStatus.dropped) {
        _log('[NOTIFIER] onStatePush: I was dropped!');
      }
      if (_state == null || newState.sequenceNumber > _state!.sequenceNumber) {
        final oldRoundCount = _state?.rounds.length ?? 0;
        _state = newState;
        if (newState.session.phase == DraftPhase.cancelled) {
          leaveDraft();
          return;
        }
        if (newState.rounds.length > oldRoundCount &&
            newState.rounds.isNotEmpty) {
          _notifyNewRoundForDevice(newState.rounds.last, _myDeviceId);
        }
        notifyListeners();
      }
    };

    // On BLE disconnect, auto-reconnect to the same leader
    // as long as this device hasn't intentionally left the draft.
    _leaderConnectedSub = follower.leaderConnected.listen((connected) {
      if (!connected && _state != null && _role == DraftRole.follower) {
        _attemptReconnect(leaderDeviceId);
      }
    });

    _bleService = follower;

    try {
      final state = await follower.connectToLeader(leaderDeviceId);
      _role = DraftRole.follower;
      _state = state;
      notifyListeners();

      await follower.sendCommand(
        JoinRequest(playerName: playerName, deviceName: _myDeviceId),
      );

      await _waitForStateUpdate();
    } catch (_) {
      // Initial connect failed; let the reconnect loop retry in the background.
      _role = DraftRole.follower;
      _attemptReconnect(leaderDeviceId);
    }
  }

  /// Auto-reconnect loop with exponential backoff.
  /// Exits when the device is no longer a follower or the draft is gone
  /// (e.g. [leaveDraft] or [dropFromDraft] was called).
  Future<void> _attemptReconnect(String leaderDeviceId) async {
    if (_isReconnecting) return;
    _isReconnecting = true;
    notifyListeners();

    for (final delay in _reconnectDelaysSeconds) {
      if (_role != DraftRole.follower) break;

      await Future.delayed(Duration(seconds: delay));

      if (_role != DraftRole.follower) break;
      final bleService = _bleService;
      if (bleService == null) break;

      try {
        final state = await bleService.reconnectToLeader(leaderDeviceId);
        if (_role == DraftRole.follower &&
            _myPlayerName != null &&
            state.getPlayer(_myDeviceId) == null) {
          // The join request was lost in the disconnect race; re-join so
          // this device is not left connected but invisible to the lobby.
          _log(
            '[NOTIFIER] reconnect: player missing from state, re-sending JoinRequest',
          );
          try {
            await bleService.sendCommand(
              JoinRequest(playerName: _myPlayerName!, deviceName: _myDeviceId),
            );
          } catch (_) {}
        }
        _isReconnecting = false;
        notifyListeners();
        return;
      } catch (_) {
        // Retry with next delay
      }
    }

    _isReconnecting = false;
    await leaveDraft();
  }

  /// Sends a [DropRequest] to the leader, then tears down locally.
  Future<void> dropFromDraft() async {
    if (isFollower && _bleService != null) {
      try {
        await _bleService!.sendCommand(DropRequest());
      } catch (_) {}
    }
    await leaveDraft();
  }

  /// Leader-only: forcefully removes a player from the draft.
  Future<void> removePlayer(String deviceId) async {
    if (!isLeader) return;
    _handleDropRequest(deviceId);
  }

  /// Sends a [MatchResult] command. Followers send over BLE; the leader
  /// processes it locally. Silently ignored when reconnecting to avoid
  /// attempting a write on a disconnected BLE link.
  Future<void> submitResult({
    required int roundNumber,
    required String matchId,
    required int myWins,
    required int opponentWins,
  }) async {
    if (isFollower && isReconnecting) return;

    final cmd = MatchResult(
      roundNumber: roundNumber,
      matchId: matchId,
      myWins: myWins,
      opponentWins: opponentWins,
    );

    if (isLeader) {
      _handleMatchResult(_myDeviceId, cmd);
      return;
    }

    if (!isFollower) return;

    await _bleService!.sendCommand(cmd);

    await _waitForStateUpdate();
  }

  /// Sends a [SubmitDecklist] command. Followers send over BLE; the leader
  /// processes it locally. Silently ignored when reconnecting to avoid
  /// attempting a write on a disconnected BLE link.
  ///
  /// Returns `true` if the decklist was accepted (the leader's state now
  /// contains it), `false` if the write failed or the update could not be
  /// confirmed — callers should surface this to the user.
  Future<bool> submitDecklist({
    required List<String> mainboardScryfallIds,
    required List<String> sideboardScryfallIds,
  }) async {
    if (isFollower && isReconnecting) return false;

    final cmd = SubmitDecklist(
      mainboardScryfallIds: mainboardScryfallIds,
      sideboardScryfallIds: sideboardScryfallIds,
    );

    if (isLeader) {
      _handleDecklistSubmission(_myDeviceId, cmd);
      return hasSubmittedDecklist(_myDeviceId);
    }

    if (!isFollower) return false;

    try {
      await _bleService!.sendCommand(cmd);
      await _waitForStateUpdate();
    } catch (_) {
      return false;
    }
    return hasSubmittedDecklist(_myDeviceId);
  }

  /// Reconciles with the leader by forcing a fresh state push via
  /// unsubscribe+resubscribe on the state characteristic. Called on screen
  /// entry and app resume so followers recover any dropped notifications
  /// without periodic polling.
  ///
  /// State sync is notification-only: the leader pushes the full [DraftState]
  /// on every change (and on every subscribe), so a resubscribe is the only
  /// read-style fallback needed — it avoids Android's stale GATT read cache
  /// and works identically on iOS.
  Future<void> refreshFromLeader() async {
    if (!isFollower || _state == null || _bleService == null) return;
    try {
      final fresh = await _bleService!.resubscribeAndReadState();
      if (fresh != null &&
          fresh.sequenceNumber > (_state?.sequenceNumber ?? -1)) {
        _state = fresh;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// After sending a command to the leader, waits for the state-update
  /// notification the leader sends in response (polling [state] every 100ms
  /// for up to 1s). Falls back to a full resubscribe only if the
  /// notification is lost — avoiding the unreliable GATT read cache on
  /// Android and the unsubscribe gap in the common case.
  Future<void> _waitForStateUpdate() async {
    if (_state == null) return;
    final oldSeq = _state!.sequenceNumber;

    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_state == null) return;
      if (_state!.sequenceNumber > oldSeq) return;
    }

    if (_state == null) return;
    try {
      final fresh = await _bleService!.resubscribeAndReadState();
      if (fresh != null &&
          fresh.sequenceNumber > (_state?.sequenceNumber ?? -1)) {
        _state = fresh;
        notifyListeners();
      }
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Notification helpers
  // -------------------------------------------------------------------------

  void _notifyMatchResultSubmitted(String reporterId, DraftMatch match) {
    if (_state == null) return;
    final reporter = _state!.getPlayer(reporterId);
    if (reporter == null) return;

    final opponentId = match.playerAId == reporterId
        ? match.playerBId
        : match.playerAId;
    final opponent = opponentId != null ? _state!.getPlayer(opponentId) : null;

    final reporterWins = match.playerAId == reporterId
        ? match.aWins
        : match.bWins;
    final opponentWins = match.playerAId == reporterId
        ? match.bWins
        : match.aWins;

    NotificationService.instance.notifyMatchResultSubmitted(
      reporterName: reporter.playerName,
      opponentName: opponent?.playerName ?? 'Bye',
      reporterWins: reporterWins ?? 0,
      opponentWins: opponentWins ?? 0,
      roundNumber: match.roundNumber,
    );
  }

  void _notifyNewRoundForDevice(DraftRound round, String deviceId) {
    if (_state == null) return;
    final match = _state!.getMyMatch(deviceId, round.roundNumber);
    String? opponentName;
    if (match != null && !match.isBye) {
      final opponentId = match.playerAId == deviceId
          ? match.playerBId
          : match.playerAId;
      if (opponentId != null) {
        opponentName = _state!.getPlayer(opponentId)?.playerName;
      }
    }
    NotificationService.instance.notifyNewRound(
      roundNumber: round.roundNumber,
      totalRounds: _state!.session.totalRounds,
      opponentName: opponentName,
    );
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /// Leaves the current draft — stops BLE and resets all local state.
  Future<void> leaveDraft() async {
    _isReconnecting = false;

    final wasLeader = isLeader;
    final oldState = _state;
    final bleService = _bleService;

    _role = DraftRole.none;
    _state = null;
    _myPlayerName = null;
    _bleToAppId.clear();

    _leaderConnectedSub?.cancel();
    _leaderConnectedSub = null;

    if (wasLeader && oldState != null && bleService != null) {
      final cancelledState = oldState
          .copyWith(
            session: oldState.session.copyWith(phase: DraftPhase.cancelled),
          )
          .bumpSequence();
      try {
        await bleService.pushState(cancelledState);
      } catch (_) {}
    }

    if (bleService != null) {
      await bleService.stop();
    }
    _bleService = null;

    notifyListeners();
  }

  @override
  void dispose() {
    _isReconnecting = false;
    _leaderConnectedSub?.cancel();
    _leaderConnectedSub = null;
    _role = DraftRole.none;
    _state = null;
    _bleToAppId.clear();
    if (_bleService != null) {
      _bleService!.stop();
    }
    super.dispose();
  }
}

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print(msg);
}

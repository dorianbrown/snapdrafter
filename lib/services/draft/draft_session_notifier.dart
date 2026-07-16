import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'draft_state.dart';
import 'draft_message.dart';
import 'draft_ble_service.dart';
import 'draft_ble_leader.dart';
import 'draft_ble_follower.dart';
import 'leader_election.dart';
import 'swiss_pairing.dart';

enum DraftRole { none, leader, follower }

class DraftSessionNotifier extends ChangeNotifier {
  DraftBleService? _bleService;
  DraftState? _state;
  DraftRole _role = DraftRole.none;
  final String _myDeviceId;
  String? _myPlayerName;
  StreamSubscription? _followerConnectedSub;
  StreamSubscription? _followerDisconnectedSub;

  DraftSessionNotifier({required String myDeviceId})
      : _myDeviceId = myDeviceId;

  DraftState? get state => _state;
  DraftRole get role => _role;
  bool get isLeader => _role == DraftRole.leader;
  bool get isFollower => _role == DraftRole.follower;
  bool get isActive => _state != null &&
      _state!.session.phase != DraftPhase.complete;
  String? get myPlayerName => _myPlayerName;
  String get myDeviceId => _myDeviceId;

  bool hasReportedResult(int roundNumber) {
    if (_state == null) return false;
    final myMatch = _state!.getMyMatch(_myDeviceId, roundNumber);
    if (myMatch == null) return false;
    return myMatch.status == MatchStatus.reported ||
        myMatch.status == MatchStatus.confirmed;
  }

  bool canReportResult(int roundNumber) {
    if (_state == null) return false;
    final myMatch = _state!.getMyMatch(_myDeviceId, roundNumber);
    if (myMatch == null) return false;
    if (myMatch.isBye) return false;
    return myMatch.status == MatchStatus.pending;
  }

  Future<void> createAndHost({
    required String name,
    String? setCode,
    String? cubeId,
    required int seatCount,
    required String playerName,
  }) async {
    await _bleService?.stop();
    _myPlayerName = playerName;

    final state = DraftState.create(
      name: name,
      leaderDeviceId: _myDeviceId,
      setCode: setCode,
      cubeId: cubeId,
      seatCount: seatCount,
    );

    final leader = DraftBleLeader();
    leader.onCommandReceived = _handleCommand;
    await leader.startAsLeader(state);

    _bleService = leader;
    _role = DraftRole.leader;
    _state = state;
    notifyListeners();
  }

  Future<void> closeLobby() async {
    if (!isLeader || _state == null) return;

    final acceptedPlayers = _state!.players
        .where((p) => p.status == PlayerStatus.accepted)
        .toList();

    final shuffled = [...acceptedPlayers]..shuffle(Random());
    final seated = <DraftPlayer>[];
    for (var i = 0; i < shuffled.length; i++) {
      seated.add(shuffled[i].copyWith(seatNumber: i + 1));
    }

    final remaining = _state!.players
        .where((p) => p.status != PlayerStatus.accepted)
        .toList();

    final pairer = SwissPairing();
    final round1Matches = pairer.pairRound(1, seated, []);
    final round1 = DraftRound(roundNumber: 1, matches: round1Matches);

    _state = _state!.copyWith(
      players: [...seated, ...remaining],
      rounds: [round1],
      session: _state!.session.copyWith(phase: DraftPhase.inProgress),
    ).bumpSequence();

    await (_bleService as DraftBleLeader).pushState(_state!);
    notifyListeners();
  }

  Future<void> advanceRound() async {
    if (!isLeader || _state == null) return;

    final nextRoundNumber = _state!.rounds.length + 1;
    if (nextRoundNumber > _state!.session.totalRounds) {
      _state = _state!.copyWith(
        session: _state!.session.copyWith(phase: DraftPhase.complete),
      ).bumpSequence();
      await (_bleService as DraftBleLeader).pushState(_state!);
      notifyListeners();
      return;
    }

    final acceptedPlayers = _state!.acceptedPlayers;
    final pairer = SwissPairing();
    final matches = pairer.pairRound(nextRoundNumber, acceptedPlayers, _state!.rounds);
    final round = DraftRound(roundNumber: nextRoundNumber, matches: matches);

    _state = _state!.copyWith(
      rounds: [..._state!.rounds, round],
    ).bumpSequence();

    await (_bleService as DraftBleLeader).pushState(_state!);
    notifyListeners();
  }

  void _handleCommand(String deviceId, DraftCommand cmd) {
    if (!isLeader || _state == null) return;

    switch (cmd) {
      case JoinRequest(:final playerName, :final deviceName):
        _handleJoinRequest(deviceId, playerName, deviceName);
      case MatchResult result:
        _handleMatchResult(deviceId, result);
      case DropRequest():
        _handleDropRequest(deviceId);
    }
  }

  void _handleJoinRequest(String deviceId, String playerName, String deviceName) {
    final existing = _state!.getPlayer(deviceId);
    if (existing != null && existing.status == PlayerStatus.accepted) return;

    final joinOrder = _state!.players
        .map((p) => p.joinOrder)
        .fold<int>(0, (max, o) => o > max ? o : max) + 1;

    final newPlayer = DraftPlayer(
      deviceId: deviceId,
      playerName: playerName,
      deviceName: deviceName,
      joinOrder: joinOrder,
      status: PlayerStatus.accepted,
    );

    _state = _state!.copyWith(
      players: [..._state!.players, newPlayer],
    ).bumpSequence();

    (_bleService as DraftBleLeader).pushState(_state!);
    notifyListeners();
  }

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

    final currentA = match.aWins;
    final currentB = match.bWins;

    int? newAWins;
    int? newBWins;
    int? newDraws;

    if (isPlayerA) {
      newAWins = result.myWins;
      newBWins = result.opponentWins;
      newDraws = result.draws;
    } else {
      newBWins = result.myWins;
      newAWins = result.opponentWins;
      newDraws = result.draws;
    }

    if (currentA != null && currentB != null) {
      if (currentA != newAWins || currentB != newBWins) {
        final updatedMatch = match.copyWith(
          status: MatchStatus.conflicted,
        );
        _updateMatch(result.roundNumber, matchIndex, updatedMatch);
        return;
      }
    }

    final newStatus = (currentA != null || currentB != null)
        ? MatchStatus.confirmed
        : MatchStatus.reported;

    final updatedMatch = match.copyWith(
      aWins: newAWins,
      bWins: newBWins,
      draws: newDraws,
      status: newStatus,
    );

    _updateMatch(result.roundNumber, matchIndex, updatedMatch);

    if (newStatus == MatchStatus.confirmed) {
      _updatePlayerRecords(match, result.roundNumber);
    }
  }

  void _updateMatch(int roundNumber, int matchIndex, DraftMatch updatedMatch) {
    final rounds = _state!.rounds.toList();
    final roundIndex = rounds.indexWhere((r) => r.roundNumber == roundNumber);
    if (roundIndex == -1) return;

    final matches = rounds[roundIndex].matches.toList();
    matches[matchIndex] = updatedMatch;

    final allComplete = matches.every((m) =>
        m.status == MatchStatus.confirmed || m.isBye);

    rounds[roundIndex] = rounds[roundIndex].copyWith(
      matches: matches,
      complete: allComplete,
    );

    _state = _state!.copyWith(rounds: rounds).bumpSequence();
    (_bleService as DraftBleLeader).pushState(_state!);
    notifyListeners();
  }

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
    (_bleService as DraftBleLeader).pushState(_state!);
    notifyListeners();
  }

  void _handleDropRequest(String deviceId) {
    final playerIndex = _state!.players.indexWhere((p) => p.deviceId == deviceId);
    if (playerIndex == -1) return;

    final updatedPlayers = _state!.players.toList();
    updatedPlayers[playerIndex] = updatedPlayers[playerIndex].copyWith(
      status: PlayerStatus.dropped,
    );

    _state = _state!.copyWith(players: updatedPlayers).bumpSequence();
    (_bleService as DraftBleLeader).pushState(_state!);
    notifyListeners();
  }

  Future<void> joinDraft({
    required String leaderDeviceId,
    required String playerName,
  }) async {
    await _bleService?.stop();
    _myPlayerName = playerName;

    final follower = DraftBleFollower();
    follower.onStatePush = (newState) {
      if (_state == null ||
          newState.sequenceNumber > _state!.sequenceNumber) {
        _state = newState;
        notifyListeners();
      }
    };

    List<String> leaderDeviceRef = [leaderDeviceId];

    follower.leaderConnected.listen((connected) {
      if (!connected && _state != null) {
        _onLeaderDisconnected(leaderDeviceRef[0]);
      }
    });

    final state = await follower.connectToLeader(leaderDeviceId);
    _bleService = follower;
    _role = DraftRole.follower;
    _state = state;
    notifyListeners();

    await follower.sendCommand(JoinRequest(
      playerName: playerName,
      deviceName: _myDeviceId,
    ));
  }

  Future<void> submitResult({
    required int roundNumber,
    required String matchId,
    required int myWins,
    required int opponentWins,
    required int draws,
  }) async {
    if (!isFollower) return;

    final cmd = MatchResult(
      roundNumber: roundNumber,
      matchId: matchId,
      myWins: myWins,
      opponentWins: opponentWins,
      draws: draws,
    );

    await (_bleService as DraftBleFollower).sendCommand(cmd);
  }

  Future<void> _onLeaderDisconnected(String previousLeaderDeviceId) async {
    if (_state == null || !isFollower) return;

    final follower = _bleService as DraftBleFollower;
    final state = _state!;

    final result = await LeaderElection().handleLeaderLost(
      lastKnownState: state,
      myDeviceId: _myDeviceId,
      currentFollower: follower,
      createLeader: () {
        final leader = DraftBleLeader();
        leader.onCommandReceived = _handleCommand;
        return leader;
      },
    );

    switch (result) {
      case FollowNewLeader(:final leaderDeviceId):
        await joinDraft(
          leaderDeviceId: leaderDeviceId,
          playerName: _myPlayerName ?? '',
        );
      case PromotedToLeader(:final leader):
        _bleService = leader;
        _role = DraftRole.leader;
        notifyListeners();
      case WaitForLeader():
        break;
    }
  }

  Future<void> leaveDraft() async {
    if (_bleService != null) {
      await _bleService!.stop();
    }
    await _followerConnectedSub?.cancel();
    await _followerDisconnectedSub?.cancel();
    _bleService = null;
    _state = null;
    _role = DraftRole.none;
    _myPlayerName = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _followerConnectedSub?.cancel();
    _followerDisconnectedSub?.cancel();
    _bleService?.stop();
    super.dispose();
  }
}

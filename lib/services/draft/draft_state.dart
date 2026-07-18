import 'dart:math';

/// Immutable data model for a draft session.
///
/// The full [DraftState] tree is serialized to JSON and broadcast from the
/// BLE leader to every follower whenever state changes. Sequences are
/// tracked via [DraftState.sequenceNumber] so followers can ignore stale
/// updates.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum DraftPhase {
  advertising,
  lobby,
  seatingsAssigned,
  inProgress,
  complete,
  cancelled;

  String get name {
    switch (this) {
      case DraftPhase.advertising:
        return 'advertising';
      case DraftPhase.lobby:
        return 'lobby';
      case DraftPhase.seatingsAssigned:
        return 'seatings_assigned';
      case DraftPhase.inProgress:
        return 'in_progress';
      case DraftPhase.complete:
        return 'complete';
      case DraftPhase.cancelled:
        return 'cancelled';
    }
  }

  static DraftPhase fromString(String value) {
    return DraftPhase.values.firstWhere(
      (p) => p.name == value,
      orElse: () => DraftPhase.lobby,
    );
  }
}

enum PlayerStatus {
  pending,
  accepted,
  dropped;

  String get name {
    switch (this) {
      case PlayerStatus.pending:
        return 'pending';
      case PlayerStatus.accepted:
        return 'accepted';
      case PlayerStatus.dropped:
        return 'dropped';
    }
  }

  static PlayerStatus fromString(String value) {
    return PlayerStatus.values.firstWhere(
      (p) => p.name == value,
      orElse: () => PlayerStatus.pending,
    );
  }
}

enum MatchStatus {
  pending,
  reported,
  confirmed,
  conflicted;

  String get name {
    switch (this) {
      case MatchStatus.pending:
        return 'pending';
      case MatchStatus.reported:
        return 'reported';
      case MatchStatus.confirmed:
        return 'confirmed';
      case MatchStatus.conflicted:
        return 'conflicted';
    }
  }

  static MatchStatus fromString(String value) {
    return MatchStatus.values.firstWhere(
      (p) => p.name == value,
      orElse: () => MatchStatus.pending,
    );
  }
}

// ---------------------------------------------------------------------------
// DraftPlayer
// ---------------------------------------------------------------------------

class DraftPlayer {
  final String deviceId;
  final String playerName;
  final String deviceName;
  final int? seatNumber;
  final int joinOrder;
  final PlayerStatus status;
  final int matchWins;
  final int matchLosses;
  final int matchDraws;

  const DraftPlayer({
    required this.deviceId,
    required this.playerName,
    required this.deviceName,
    this.seatNumber,
    required this.joinOrder,
    this.status = PlayerStatus.pending,
    this.matchWins = 0,
    this.matchLosses = 0,
    this.matchDraws = 0,
  });

  /// Tournament match points: 3 per win, 1 per draw.
  int get matchPoints => matchWins * 3 + matchDraws;

  /// Game win percentage used as a secondary tiebreaker.
  /// Draws count as half a win toward game percentage.
  double get gameWinPercentage {
    final totalGames = matchWins + matchLosses + matchDraws;
    if (totalGames == 0) return 0.0;
    return (matchWins + matchDraws * 0.5) / totalGames;
  }

  DraftPlayer copyWith({
    String? deviceId,
    String? playerName,
    String? deviceName,
    int? seatNumber,
    int? joinOrder,
    PlayerStatus? status,
    int? matchWins,
    int? matchLosses,
    int? matchDraws,
    bool clearSeat = false,
  }) {
    return DraftPlayer(
      deviceId: deviceId ?? this.deviceId,
      playerName: playerName ?? this.playerName,
      deviceName: deviceName ?? this.deviceName,
      seatNumber: clearSeat ? null : (seatNumber ?? this.seatNumber),
      joinOrder: joinOrder ?? this.joinOrder,
      status: status ?? this.status,
      matchWins: matchWins ?? this.matchWins,
      matchLosses: matchLosses ?? this.matchLosses,
      matchDraws: matchDraws ?? this.matchDraws,
    );
  }

  Map<String, dynamic> toJson() => {
    'd': deviceId,
    'n': playerName,
    if (seatNumber != null) 't': seatNumber,
    'j': joinOrder,
    's': status.name,
    if (matchWins != 0) 'mw': matchWins,
    if (matchLosses != 0) 'ml': matchLosses,
    if (matchDraws != 0) 'md': matchDraws,
  };

  factory DraftPlayer.fromJson(Map<String, dynamic> json) {
    return DraftPlayer(
      deviceId: json['d'] as String,
      playerName: json['n'] as String,
      deviceName: json['deviceName'] as String? ?? '',
      seatNumber: json['t'] as int?,
      joinOrder: json['j'] as int,
      status: PlayerStatus.fromString(json['s'] as String),
      matchWins: json['mw'] as int? ?? 0,
      matchLosses: json['ml'] as int? ?? 0,
      matchDraws: json['md'] as int? ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// DraftMatch
// ---------------------------------------------------------------------------

class DraftMatch {
  final String matchId;
  final int roundNumber;
  final String playerAId;
  final String? playerBId;
  final int? aWins;
  final int? bWins;
  final int? draws;
  final MatchStatus status;

  const DraftMatch({
    required this.matchId,
    required this.roundNumber,
    required this.playerAId,
    this.playerBId,
    this.aWins,
    this.bWins,
    this.draws,
    this.status = MatchStatus.pending,
  });

  /// A match is a bye when there is no opponent (odd player count round).
  bool get isBye => playerBId == null;

  DraftMatch copyWith({
    String? matchId,
    int? roundNumber,
    String? playerAId,
    String? playerBId,
    int? aWins,
    int? bWins,
    int? draws,
    MatchStatus? status,
    bool clearPlayerB = false,
  }) {
    return DraftMatch(
      matchId: matchId ?? this.matchId,
      roundNumber: roundNumber ?? this.roundNumber,
      playerAId: playerAId ?? this.playerAId,
      playerBId: clearPlayerB ? null : (playerBId ?? this.playerBId),
      aWins: aWins ?? this.aWins,
      bWins: bWins ?? this.bWins,
      draws: draws ?? this.draws,
      status: status ?? this.status,
    );
  }

  /// Returns the winner's device ID, or `null` if the match is not yet
  /// confirmed or ended in a draw.
  String? winnerId() {
    if (status != MatchStatus.confirmed) return null;
    if (isBye) return playerAId;
    if (aWins == null || bWins == null) return null;
    if (aWins! > bWins!) return playerAId;
    if (bWins! > aWins!) return playerBId;
    return null;
  }

  Map<String, dynamic> toJson() => {
    'i': matchId,
    'r': roundNumber,
    'a': playerAId,
    if (playerBId != null) 'b': playerBId,
    if (aWins != null) 'aw': aWins,
    if (bWins != null) 'bw': bWins,
    if (draws != null) 'dr': draws,
    's': status.name,
  };

  factory DraftMatch.fromJson(Map<String, dynamic> json) {
    return DraftMatch(
      matchId: json['i'] as String,
      roundNumber: json['r'] as int,
      playerAId: json['a'] as String,
      playerBId: json['b'] as String?,
      aWins: json['aw'] as int?,
      bWins: json['bw'] as int?,
      draws: json['dr'] as int?,
      status: MatchStatus.fromString(json['s'] as String),
    );
  }
}

// ---------------------------------------------------------------------------
// DraftRound
// ---------------------------------------------------------------------------

class DraftRound {
  final int roundNumber;
  final List<DraftMatch> matches;
  final bool complete;
  final DateTime? roundStartTime;

  const DraftRound({
    required this.roundNumber,
    required this.matches,
    this.complete = false,
    this.roundStartTime,
  });

  DraftRound copyWith({
    int? roundNumber,
    List<DraftMatch>? matches,
    bool? complete,
    DateTime? roundStartTime,
    bool clearRoundStartTime = false,
  }) {
    return DraftRound(
      roundNumber: roundNumber ?? this.roundNumber,
      matches: matches ?? this.matches,
      complete: complete ?? this.complete,
      roundStartTime:
          clearRoundStartTime ? null : (roundStartTime ?? this.roundStartTime),
    );
  }

  Map<String, dynamic> toJson() => {
    'r': roundNumber,
    'm': matches.map((m) => m.toJson()).toList(),
    'c': complete,
    if (roundStartTime != null)
      't': roundStartTime!.toUtc().toIso8601String(),
  };

  factory DraftRound.fromJson(Map<String, dynamic> json) {
    return DraftRound(
      roundNumber: json['r'] as int,
      matches: (json['m'] as List<dynamic>)
          .map((m) => DraftMatch.fromJson(m as Map<String, dynamic>))
          .toList(),
      complete: json['c'] as bool? ?? false,
      roundStartTime: json['t'] != null
          ? DateTime.parse(json['t'] as String)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// DraftSession
// ---------------------------------------------------------------------------

class DraftSession {
  final String sessionId;
  final String name;
  final String? setCode;
  final String? cubeId;
  final int seatCount;
  final DraftPhase phase;
  final int totalRounds;
  final int roundDurationSeconds;
  final DateTime createdAt;

  const DraftSession({
    required this.sessionId,
    required this.name,
    this.setCode,
    this.cubeId,
    required this.seatCount,
    this.phase = DraftPhase.lobby,
    required this.totalRounds,
    this.roundDurationSeconds = 300,
    required this.createdAt,
  });

  DraftSession copyWith({
    String? sessionId,
    String? name,
    String? setCode,
    String? cubeId,
    int? seatCount,
    DraftPhase? phase,
    int? totalRounds,
    int? roundDurationSeconds,
    DateTime? createdAt,
    bool clearSetCode = false,
    bool clearCubeId = false,
  }) {
    return DraftSession(
      sessionId: sessionId ?? this.sessionId,
      name: name ?? this.name,
      setCode: clearSetCode ? null : (setCode ?? this.setCode),
      cubeId: clearCubeId ? null : (cubeId ?? this.cubeId),
      seatCount: seatCount ?? this.seatCount,
      phase: phase ?? this.phase,
      totalRounds: totalRounds ?? this.totalRounds,
      roundDurationSeconds: roundDurationSeconds ?? this.roundDurationSeconds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'i': sessionId,
    'n': name,
    if (setCode != null) 'c': setCode,
    if (cubeId != null) 'u': cubeId,
    'k': seatCount,
    'h': phase.name,
    't': totalRounds,
    'd': roundDurationSeconds,
    'a': createdAt.toIso8601String(),
  };

  factory DraftSession.fromJson(Map<String, dynamic> json) {
    return DraftSession(
      sessionId: json['i'] as String,
      name: json['n'] as String,
      setCode: json['c'] as String?,
      cubeId: json['u'] as String?,
      seatCount: json['k'] as int,
      phase: DraftPhase.fromString(json['h'] as String),
      totalRounds: json['t'] as int,
      roundDurationSeconds: json['d'] as int? ?? 300,
      createdAt: DateTime.parse(json['a'] as String),
    );
  }
}

// ---------------------------------------------------------------------------
// DraftState — root state object synchronized over BLE
// ---------------------------------------------------------------------------

class DraftState {
  /// Monotonically increasing counter; followers ignore updates with a lower
  /// number than what they already have.
  final int sequenceNumber;
  final DraftSession session;
  final List<DraftPlayer> players;
  final List<DraftRound> rounds;

  const DraftState({
    required this.sequenceNumber,
    required this.session,
    this.players = const [],
    this.rounds = const [],
  });

  /// The device that joined first (lowest [joinOrder]) acts as the leader.
  String? get leaderDeviceId {
    if (players.isEmpty) return null;
    final sorted = [...players]..sort((a, b) => a.joinOrder.compareTo(b.joinOrder));
    return sorted.first.deviceId;
  }

  /// Players whose status is [PlayerStatus.accepted].
  List<DraftPlayer> get acceptedPlayers =>
      players.where((p) => p.status == PlayerStatus.accepted).toList();

  /// Players who have not dropped (includes pending and accepted).
  List<DraftPlayer> get activePlayers =>
      players.where((p) => p.status != PlayerStatus.dropped).toList();

  DraftPlayer? getPlayer(String deviceId) {
    try {
      return players.firstWhere((p) => p.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  /// Looks up this device's match in a given round.
  DraftMatch? getMyMatch(String deviceId, int roundNumber) {
    try {
      return rounds.firstWhere((r) => r.roundNumber == roundNumber).matches
          .firstWhere((m) =>
              m.playerAId == deviceId || m.playerBId == deviceId);
    } catch (_) {
      return null;
    }
  }

  /// Calculates tournament standings sorted by:
  ///   1. Match points (3 per win, 1 per draw)
  ///   2. Opponent match-win percentage (OMW% — primary tiebreaker)
  ///   3. Game win percentage (secondary tiebreaker)
  List<DraftPlayer> get standings {
    final active = acceptedPlayers;
    final opponents = <String, List<String>>{};
    final gameWinRecords = <String, List<int>>{};

    for (final round in rounds) {
      for (final match in round.matches) {
        if (match.playerBId == null) continue;
        opponents.putIfAbsent(match.playerAId, () => []).add(match.playerBId!);
        opponents.putIfAbsent(match.playerBId!, () => []).add(match.playerAId);
        if (match.aWins != null && match.bWins != null) {
          gameWinRecords.putIfAbsent(match.playerAId, () => []).add(match.aWins!);
          gameWinRecords.putIfAbsent(match.playerBId!, () => []).add(match.bWins!);
        }
      }
    }

    double? opponentMatchWinPercent(String playerId) {
      final opps = opponents[playerId];
      if (opps == null || opps.isEmpty) return 0.0;
      final oppMWP = opps.map((oppId) {
        final opp = getPlayer(oppId);
        if (opp == null) return 0.0;
        final totalMatches = opp.matchWins + opp.matchLosses + opp.matchDraws;
        if (totalMatches == 0) return 0.0;
        return (opp.matchWins * 3 + opp.matchDraws) / (totalMatches * 3);
      }).toList();
      return oppMWP.reduce((a, b) => a + b) / oppMWP.length;
    }

    final sorted = [...active]..sort((a, b) {
      final pointsCompare = b.matchPoints.compareTo(a.matchPoints);
      if (pointsCompare != 0) return pointsCompare;
      final omwpA = opponentMatchWinPercent(a.deviceId) ?? 0.0;
      final omwpB = opponentMatchWinPercent(b.deviceId) ?? 0.0;
      final omwpCompare = omwpB.compareTo(omwpA);
      if (omwpCompare != 0) return omwpCompare;
      return b.gameWinPercentage.compareTo(a.gameWinPercentage);
    });

    return sorted;
  }

  DraftState copyWith({
    int? sequenceNumber,
    DraftSession? session,
    List<DraftPlayer>? players,
    List<DraftRound>? rounds,
  }) {
    return DraftState(
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      session: session ?? this.session,
      players: players ?? this.players,
      rounds: rounds ?? this.rounds,
    );
  }

  /// Returns a copy with the sequence number incremented by one.
  DraftState bumpSequence() => copyWith(sequenceNumber: sequenceNumber + 1);

  Map<String, dynamic> toJson() => {
    'q': sequenceNumber,
    's': session.toJson(),
    'p': players.map((p) => p.toJson()).toList(),
    'r': rounds.map((r) => r.toJson()).toList(),
  };

  factory DraftState.fromJson(Map<String, dynamic> json) {
    return DraftState(
      sequenceNumber: json['q'] as int,
      session: DraftSession.fromJson(json['s'] as Map<String, dynamic>),
      players: (json['p'] as List<dynamic>)
          .map((p) => DraftPlayer.fromJson(p as Map<String, dynamic>))
          .toList(),
      rounds: (json['r'] as List<dynamic>?)
          ?.map((r) => DraftRound.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  /// Creates a brand-new draft session with the host already seated at
  /// position 1. [totalRounds] is derived as `log2(seatCount)` clamped to
  /// the range [3, 6].
  static DraftState create({
    required String name,
    required String leaderDeviceId,
    String? setCode,
    String? cubeId,
    required int seatCount,
    int roundDurationSeconds = 300,
  }) {
    final sessionId = _generateId();
    final totalRounds = (log2(seatCount).ceil()).clamp(3, 6);

    return DraftState(
      sequenceNumber: 0,
      session: DraftSession(
        sessionId: sessionId,
        name: name,
        setCode: setCode,
        cubeId: cubeId,
        seatCount: seatCount,
        phase: DraftPhase.lobby,
        totalRounds: totalRounds,
        roundDurationSeconds: roundDurationSeconds,
        createdAt: DateTime.now(),
      ),
      players: [
        DraftPlayer(
          deviceId: leaderDeviceId,
          playerName: '',
          deviceName: '',
          joinOrder: 0,
          seatNumber: 1,
          status: PlayerStatus.accepted,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Integer log₂ used to determine the number of Swiss rounds from the
/// player count.
int log2(int n) {
  var count = 0;
  while (n > 1) {
    n >>= 1;
    count++;
  }
  return count;
}

final _random = Random();

/// Generates a UUID-like session ID string (e.g. "a1b2c3d4-...-").
String _generateId() {
  final chars = 'abcdef0123456789';
  String hex(int len) => List.generate(
        len,
        (_) => chars[_random.nextInt(chars.length)],
      ).join();

  return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
}

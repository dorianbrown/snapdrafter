/// Commands sent from a follower to the leader over BLE.
///
/// Each command maps to a [DraftCommandType] and is serialized as JSON
/// written to the leader's command characteristic.
enum DraftCommandType {
  joinRequest,
  matchResult,
  dropRequest,
  submitDecklist,
  stateAck,
  resyncRequest,
  decklistRequest;

  String get name {
    switch (this) {
      case DraftCommandType.joinRequest:
        return 'join_request';
      case DraftCommandType.matchResult:
        return 'match_result';
      case DraftCommandType.dropRequest:
        return 'drop_request';
      case DraftCommandType.submitDecklist:
        return 'submit_decklist';
      case DraftCommandType.stateAck:
        return 'state_ack';
      case DraftCommandType.resyncRequest:
        return 'resync_request';
      case DraftCommandType.decklistRequest:
        return 'decklist_request';
    }
  }

  static DraftCommandType fromString(String value) {
    return DraftCommandType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => DraftCommandType.joinRequest,
    );
  }
}

sealed class DraftCommand {
  /// App-level device id of the sender. Preserved end-to-end so commands can
  /// be routed through relay nodes without losing the originating player.
  final String src;

  DraftCommand({this.src = ''});

  DraftCommandType get type;

  Map<String, dynamic> toJson();

  /// Deserializes a JSON map into the correct [DraftCommand] subclass based
  /// on the `type` field.
  static DraftCommand fromJson(Map<String, dynamic> json) {
    final type = DraftCommandType.fromString(json['type'] as String);
    switch (type) {
      case DraftCommandType.joinRequest:
        return JoinRequest.fromJson(json);
      case DraftCommandType.matchResult:
        return MatchResult.fromJson(json);
      case DraftCommandType.dropRequest:
        return DropRequest.fromJson(json);
      case DraftCommandType.submitDecklist:
        return SubmitDecklist.fromJson(json);
      case DraftCommandType.stateAck:
        return StateAck.fromJson(json);
      case DraftCommandType.resyncRequest:
        return ResyncRequest.fromJson(json);
      case DraftCommandType.decklistRequest:
        return DecklistRequest.fromJson(json);
    }
  }
}

/// Sent by a follower immediately after connecting to request joining the
/// draft lobby.
class JoinRequest extends DraftCommand {
  final String playerName;
  final String deviceName;

  JoinRequest({required this.playerName, required this.deviceName, super.src});

  @override
  DraftCommandType get type => DraftCommandType.joinRequest;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'src': src,
    'playerName': playerName,
    'deviceName': deviceName,
  };

  factory JoinRequest.fromJson(Map<String, dynamic> json) {
    return JoinRequest(
      playerName: json['playerName'] as String,
      deviceName: json['deviceName'] as String,
      src: json['src'] as String? ?? '',
    );
  }
}

/// Reports a match result from the perspective of the submitting player.
///
/// The leader maps `myWins`/`opponentWins` to the correct player A/B fields
/// and detects conflicts when two players' reports disagree.
class MatchResult extends DraftCommand {
  final int roundNumber;
  final String matchId;
  final int myWins;
  final int opponentWins;

  MatchResult({
    required this.roundNumber,
    required this.matchId,
    required this.myWins,
    required this.opponentWins,
    super.src,
  });

  @override
  DraftCommandType get type => DraftCommandType.matchResult;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'src': src,
    'roundNumber': roundNumber,
    'matchId': matchId,
    'myWins': myWins,
    'opponentWins': opponentWins,
  };

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      roundNumber: json['roundNumber'] as int,
      matchId: json['matchId'] as String,
      myWins: json['myWins'] as int,
      opponentWins: json['opponentWins'] as int,
      src: json['src'] as String? ?? '',
    );
  }
}

/// Signals that a player is voluntarily leaving the draft.
class DropRequest extends DraftCommand {
  DropRequest({super.src});

  @override
  DraftCommandType get type => DraftCommandType.dropRequest;

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'src': src};

  factory DropRequest.fromJson(Map<String, dynamic> json) {
    return DropRequest(src: json['src'] as String? ?? '');
  }
}

/// Submits a player's draft decklist to the leader for sync to all devices.
class SubmitDecklist extends DraftCommand {
  final List<String> mainboardScryfallIds;
  final List<String> sideboardScryfallIds;

  SubmitDecklist({
    required this.mainboardScryfallIds,
    required this.sideboardScryfallIds,
    super.src,
  });

  @override
  DraftCommandType get type => DraftCommandType.submitDecklist;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'src': src,
    'mb': mainboardScryfallIds,
    'sb': sideboardScryfallIds,
  };

  factory SubmitDecklist.fromJson(Map<String, dynamic> json) {
    return SubmitDecklist(
      mainboardScryfallIds: (json['mb'] as List<dynamic>).cast<String>(),
      sideboardScryfallIds: (json['sb'] as List<dynamic>).cast<String>(),
      src: json['src'] as String? ?? '',
    );
  }
}

/// Sent by a follower after applying a snapshot, carrying the applied sequence.
class StateAck extends DraftCommand {
  final int seq;

  StateAck({required this.seq, super.src});

  @override
  DraftCommandType get type => DraftCommandType.stateAck;

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'src': src, 'seq': seq};

  factory StateAck.fromJson(Map<String, dynamic> json) {
    return StateAck(seq: json['seq'] as int, src: json['src'] as String? ?? '');
  }
}

/// Sent by a follower that detected it is behind (e.g. via a tick) to request
/// a fresh snapshot from the leader.
class ResyncRequest extends DraftCommand {
  final int appliedSeq;

  ResyncRequest({required this.appliedSeq, super.src});

  @override
  DraftCommandType get type => DraftCommandType.resyncRequest;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'src': src,
    'appliedSeq': appliedSeq,
  };

  factory ResyncRequest.fromJson(Map<String, dynamic> json) {
    return ResyncRequest(
      appliedSeq: json['appliedSeq'] as int,
      src: json['src'] as String? ?? '',
    );
  }
}

/// Requests full decklist contents. [targetDeviceIds] lists the players whose
/// decklists are missing; an empty list means "all submitted decklists".
class DecklistRequest extends DraftCommand {
  final List<String> targetDeviceIds;

  DecklistRequest({this.targetDeviceIds = const [], super.src});

  @override
  DraftCommandType get type => DraftCommandType.decklistRequest;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'src': src,
    'targets': targetDeviceIds,
  };

  factory DecklistRequest.fromJson(Map<String, dynamic> json) {
    return DecklistRequest(
      targetDeviceIds: (json['targets'] as List<dynamic>? ?? []).cast<String>(),
      src: json['src'] as String? ?? '',
    );
  }
}

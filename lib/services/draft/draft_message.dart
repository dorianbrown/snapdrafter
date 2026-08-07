/// Commands sent from a follower to the leader over BLE.
///
/// Each command maps to a [DraftCommandType] and is serialized as JSON
/// written to the leader's command characteristic.
enum DraftCommandType {
  joinRequest,
  matchResult,
  dropRequest,
  submitDecklist;

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
    }
  }
}

/// Sent by a follower immediately after connecting to request joining the
/// draft lobby.
class JoinRequest extends DraftCommand {
  final String playerName;
  final String deviceName;

  JoinRequest({required this.playerName, required this.deviceName});

  @override
  DraftCommandType get type => DraftCommandType.joinRequest;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'playerName': playerName,
    'deviceName': deviceName,
  };

  factory JoinRequest.fromJson(Map<String, dynamic> json) {
    return JoinRequest(
      playerName: json['playerName'] as String,
      deviceName: json['deviceName'] as String,
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
  });

  @override
  DraftCommandType get type => DraftCommandType.matchResult;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
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
    );
  }
}

/// Signals that a player is voluntarily leaving the draft.
class DropRequest extends DraftCommand {
  DropRequest();

  @override
  DraftCommandType get type => DraftCommandType.dropRequest;

  @override
  Map<String, dynamic> toJson() => {'type': type.name};

  factory DropRequest.fromJson(Map<String, dynamic> json) {
    return DropRequest();
  }
}

/// Submits a player's draft decklist to the leader for sync to all devices.
class SubmitDecklist extends DraftCommand {
  final List<String> mainboardScryfallIds;
  final List<String> sideboardScryfallIds;

  SubmitDecklist({
    required this.mainboardScryfallIds,
    required this.sideboardScryfallIds,
  });

  @override
  DraftCommandType get type => DraftCommandType.submitDecklist;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'mb': mainboardScryfallIds,
    'sb': sideboardScryfallIds,
  };

  factory SubmitDecklist.fromJson(Map<String, dynamic> json) {
    return SubmitDecklist(
      mainboardScryfallIds: (json['mb'] as List<dynamic>).cast<String>(),
      sideboardScryfallIds: (json['sb'] as List<dynamic>).cast<String>(),
    );
  }
}

import 'draft_state.dart';

class SwissPairing {
  List<DraftMatch> pairRound(int roundNumber, List<DraftPlayer> players, List<DraftRound> previousRounds) {
    if (players.length < 2) {
      return players.isEmpty
          ? []
          : [
              DraftMatch(
                matchId: _generateMatchId(roundNumber, 0),
                roundNumber: roundNumber,
                playerAId: players.first.deviceId,
                status: MatchStatus.confirmed,
              )
            ];
    }

    final sorted = _sortByStandings(players, previousRounds);
    final paired = <String>{};
    final matches = <DraftMatch>[];
    final previouslyPaired = _buildPreviousPairs(previousRounds);

    for (var i = 0; i < sorted.length; i++) {
      if (paired.contains(sorted[i].deviceId)) continue;

      DraftPlayer? opponent;
      for (var j = i + 1; j < sorted.length; j++) {
        if (paired.contains(sorted[j].deviceId)) continue;
        if (previouslyPaired[sorted[i].deviceId]?.contains(sorted[j].deviceId) == true) {
          continue;
        }
        opponent = sorted[j];
        break;
      }

      if (opponent != null) {
        paired.add(sorted[i].deviceId);
        paired.add(opponent.deviceId);
        matches.add(DraftMatch(
          matchId: _generateMatchId(roundNumber, matches.length),
          roundNumber: roundNumber,
          playerAId: sorted[i].deviceId,
          playerBId: opponent.deviceId,
        ));
      } else if (!paired.contains(sorted[i].deviceId)) {
        paired.add(sorted[i].deviceId);
        matches.add(DraftMatch(
          matchId: _generateMatchId(roundNumber, matches.length),
          roundNumber: roundNumber,
          playerAId: sorted[i].deviceId,
          status: MatchStatus.confirmed,
        ));
      }
    }

    return matches;
  }

  Map<String, Set<String>> _buildPreviousPairs(List<DraftRound> rounds) {
    final pairs = <String, Set<String>>{};
    for (final round in rounds) {
      for (final match in round.matches) {
        if (match.playerBId == null) continue;
        pairs.putIfAbsent(match.playerAId, () => {}).add(match.playerBId!);
        pairs.putIfAbsent(match.playerBId!, () => {}).add(match.playerAId);
      }
    }
    return pairs;
  }

  List<DraftPlayer> _sortByStandings(List<DraftPlayer> players, List<DraftRound> previousRounds) {
    final opponents = <String, List<String>>{};
    final gameWinRecords = <String, List<int>>{};

    for (final round in previousRounds) {
      for (final match in round.matches) {
        if (match.playerBId == null) continue;
        opponents.putIfAbsent(match.playerAId, () => []).add(match.playerBId!);
        opponents.putIfAbsent(match.playerBId!, () => []).add(match.playerAId);
        if (match.aWins != null) {
          gameWinRecords.putIfAbsent(match.playerAId, () => []).add(match.aWins!);
        }
        if (match.bWins != null) {
          gameWinRecords.putIfAbsent(match.playerBId!, () => []).add(match.bWins!);
        }
      }
    }

    double opponentMatchWinPercent(String playerId) {
      final opps = opponents[playerId];
      if (opps == null || opps.isEmpty) return 0.0;
      final percents = opps.map((oppId) {
        final opp = players.firstWhereOrNull((p) => p.deviceId == oppId);
        if (opp == null) return 0.0;
        final total = opp.matchWins + opp.matchLosses + opp.matchDraws;
        if (total == 0) return 0.0;
        return (opp.matchWins * 3 + opp.matchDraws) / (total * 3);
      }).toList();
      if (percents.isEmpty) return 0.0;
      return percents.reduce((a, b) => a + b) / percents.length;
    }

    double gameWinPercent(String playerId) {
      final totals = gameWinRecords[playerId];
      if (totals == null || totals.isEmpty) return 0.0;
      final sum = totals.reduce((a, b) => a + b);
      final maxGames = totals.length * 3;
      return maxGames > 0 ? sum / maxGames : 0.0;
    }

    final sorted = [...players]..sort((a, b) {
      final pointsCompare = b.matchPoints.compareTo(a.matchPoints);
      if (pointsCompare != 0) return pointsCompare;
      final omwpA = opponentMatchWinPercent(a.deviceId);
      final omwpB = opponentMatchWinPercent(b.deviceId);
      final omwpCompare = omwpB.compareTo(omwpA);
      if (omwpCompare != 0) return omwpCompare;
      final gwpA = gameWinPercent(a.deviceId);
      final gwpB = gameWinPercent(b.deviceId);
      return gwpB.compareTo(gwpA);
    });

    return sorted;
  }

  String _generateMatchId(int round, int index) {
    return 'r${round}_m$index';
  }
}

extension FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

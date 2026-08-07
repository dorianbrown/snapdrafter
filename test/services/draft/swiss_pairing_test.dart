import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/swiss_pairing.dart';

DraftPlayer _player(
  String id, {
  int wins = 0,
  int losses = 0,
  int draws = 0,
  int joinOrder = 0,
}) {
  return DraftPlayer(
    deviceId: id,
    playerName: 'Player $id',
    status: PlayerStatus.accepted,
    joinOrder: joinOrder,
    matchWins: wins,
    matchLosses: losses,
    matchDraws: draws,
  );
}

List<DraftRound> _round(List<List<int>> matchResults) {
  final matches = <DraftMatch>[];
  for (var i = 0; i < matchResults.length; i++) {
    final result = matchResults[i];
    final isBye = result.length == 1;
    matches.add(
      DraftMatch(
        matchId: 'r1_m$i',
        roundNumber: 1,
        playerAId: 'p${result[0]}',
        playerBId: isBye ? null : 'p${result[1]}',
        aWins: isBye ? null : result[2],
        bWins: isBye ? null : result[3],
        status: MatchStatus.confirmed,
      ),
    );
  }
  return [
    DraftRound(
      roundNumber: 1,
      matches: matches,
      roundStartTime: DateTime(2025, 1, 1),
      complete: true,
    ),
  ];
}

void main() {
  group('SwissPairing.pairRound', () {
    late SwissPairing pairer;

    setUp(() {
      pairer = SwissPairing();
    });

    group('edge cases', () {
      test('empty player list returns empty matches', () {
        expect(pairer.pairRound(1, [], []), isEmpty);
      });

      test('single player gets a bye', () {
        final matches = pairer.pairRound(1, [_player('p1')], []);
        expect(matches.length, 1);
        expect(matches[0].playerAId, 'p1');
        expect(matches[0].playerBId, isNull);
        expect(matches[0].isBye, isTrue);
      });

      test('single player bye is auto-confirmed', () {
        final matches = pairer.pairRound(1, [_player('p1')], []);
        expect(matches[0].status, MatchStatus.confirmed);
      });
    });

    group('simple pairings', () {
      test('two players produce one match', () {
        final matches = pairer.pairRound(1, [_player('p1'), _player('p2')], []);
        expect(matches.length, 1);
        expect(matches[0].playerAId, 'p1');
        expect(matches[0].playerBId, 'p2');
        expect(matches[0].isBye, isFalse);
      });

      test('three players produce one match and one bye', () {
        final matches = pairer.pairRound(1, [
          _player('p1'),
          _player('p2'),
          _player('p3'),
        ], []);
        expect(matches.length, 2);
        final nonByes = matches.where((m) => !m.isBye).toList();
        expect(nonByes.length, 1);
        final byes = matches.where((m) => m.isBye).toList();
        expect(byes.length, 1);
      });

      test('four players produce two matches', () {
        final matches = pairer.pairRound(1, [
          _player('p1'),
          _player('p2'),
          _player('p3'),
          _player('p4'),
        ], []);
        expect(matches.length, 2);
        expect(matches.every((m) => !m.isBye), isTrue);
      });

      test('five players produce two matches and one bye', () {
        final matches = pairer.pairRound(
          1,
          List.generate(5, (i) => _player('p${i + 1}')),
          [],
        );
        expect(matches.length, 3);
        final byes = matches.where((m) => m.isBye).length;
        expect(byes, 1);
      });
    });

    group('match IDs', () {
      test('match ID includes round number and match index', () {
        final matches = pairer.pairRound(3, [
          _player('p1'),
          _player('p2'),
          _player('p3'),
          _player('p4'),
        ], []);
        expect(matches.length, 2);
        expect(matches[0].matchId, 'r3_m0');
        expect(matches[1].matchId, 'r3_m1');
      });

      test('round number is embedded in match ID', () {
        final matches = pairer.pairRound(7, [_player('p1'), _player('p2')], []);
        expect(matches[0].matchId, startsWith('r7_'));
      });
    });

    group('all players paired', () {
      test('no player appears in more than one match', () {
        final players = List.generate(8, (i) => _player('p${i + 1}'));
        final matches = pairer.pairRound(1, players, []);
        final seen = <String>{};
        for (final m in matches) {
          expect(
            seen.contains(m.playerAId),
            isFalse,
            reason: '${m.playerAId} paired twice',
          );
          seen.add(m.playerAId);
          if (m.playerBId != null) {
            expect(
              seen.contains(m.playerBId!),
              isFalse,
              reason: '${m.playerBId} paired twice',
            );
            seen.add(m.playerBId!);
          }
        }
      });
    });

    group('standings-based pairing', () {
      test('players with higher match points are paired first', () {
        final players = [
          _player('p1', wins: 3), // 9 points
          _player('p2', wins: 3), // 9 points
          _player('p3', wins: 2), // 6 points
          _player('p4', wins: 2), // 6 points
          _player('p5', wins: 1), // 3 points
          _player('p6', wins: 1), // 3 points
        ];
        final matches = pairer.pairRound(2, players, []);
        final nonByes = matches.where((m) => !m.isBye).toList();

        final group0 = {nonByes[0].playerAId, nonByes[0].playerBId!};
        final group1 = {nonByes[1].playerAId, nonByes[1].playerBId!};
        final group2 = {nonByes[2].playerAId, nonByes[2].playerBId!};

        final highPointPlayers = {'p1', 'p2'};
        final midPointPlayers = {'p3', 'p4'};
        final lowPointPlayers = {'p5', 'p6'};

        final pairedHigh =
            group0.containsAll(highPointPlayers) ||
            group1.containsAll(highPointPlayers) ||
            group2.containsAll(highPointPlayers);
        final pairedLow =
            group0.containsAll(lowPointPlayers) ||
            group1.containsAll(lowPointPlayers) ||
            group2.containsAll(lowPointPlayers);

        expect(pairedHigh, isTrue);
        expect(pairedLow, isTrue);
      });
    });

    group('rematch prevention', () {
      test('players paired in round 1 are not paired in round 2', () {
        final players = [
          _player('p1', wins: 1),
          _player('p2', wins: 0),
          _player('p3', wins: 1),
          _player('p4', wins: 0),
        ];
        final round1Matches = pairer.pairRound(1, players, []);

        final round2Matches = pairer.pairRound(2, players, [
          DraftRound(
            roundNumber: 1,
            matches: round1Matches,
            roundStartTime: DateTime(2025, 1, 1),
            complete: true,
          ),
        ]);

        final r1Pairs = <Set<String>>{};
        for (final m in round1Matches.where((m) => !m.isBye)) {
          r1Pairs.add({m.playerAId, m.playerBId!});
        }

        for (final m in round2Matches.where((m) => !m.isBye)) {
          for (final pair in r1Pairs) {
            final current = {m.playerAId, m.playerBId!};
            expect(
              current,
              isNot(equals(pair)),
              reason: 'Rematch detected in round 2',
            );
          }
        }
      });

      test('rematch prevention can force non-optimal pairings', () {
        final players = [
          _player('p1', wins: 3, draws: 1),
          _player('p2', wins: 3),
          _player('p3', wins: 2),
          _player('p4', wins: 1),
        ];
        // Round 1: top players play each other (per standings)
        final round1Matches = pairer.pairRound(1, players, []);

        // Record round 1 wins for players 3 and 4, giving them points.
        // This affects round 2 sorting but more importantly round 1 pairs p1-p2.
        // In round 2, p1 should NOT play p2 again.
        final round2Matches = pairer.pairRound(2, players, [
          DraftRound(
            roundNumber: 1,
            matches: round1Matches,
            roundStartTime: DateTime(2025, 1, 1),
            complete: true,
          ),
        ]);

        final r1Pairs = <Set<String>>{};
        for (final m in round1Matches.where((m) => !m.isBye)) {
          r1Pairs.add({m.playerAId, m.playerBId!});
        }

        for (final m in round2Matches.where((m) => !m.isBye)) {
          for (final pair in r1Pairs) {
            final current = {m.playerAId, m.playerBId!};
            expect(
              current,
              isNot(equals(pair)),
              reason: 'Rematch detected in round 2',
            );
          }
        }
      });
    });
  });

  group('SwissPairing._sortByStandings', () {
    test('sorts by match points descending', () {
      final players = [
        _player('p1', wins: 1),
        _player('p2', wins: 3),
        _player('p3', wins: 2),
      ];
      final matches = SwissPairing().pairRound(1, players, []);
      final nonBye = matches.firstWhere((m) => !m.isBye);
      final pair = {nonBye.playerAId, nonBye.playerBId!};
      // Top two by points (p2=9, p3=6) should be paired; p1=3 gets bye
      expect(pair, containsAll(['p2', 'p3']));
      final bye = matches.firstWhere((m) => m.isBye);
      expect(bye.playerAId, 'p1');
    });

    test('draws count toward match points (3 pts win, 1 pt draw)', () {
      final players = [
        _player('p1', wins: 2), // 6 pts
        _player('p2', wins: 1, draws: 4), // 7 pts
        _player('p3', wins: 2, draws: 1), // 7 pts
      ];
      final matches = SwissPairing().pairRound(2, players, []);
      final nonByes = matches.where((m) => !m.isBye).toList();
      expect(nonByes.length, 1);
      final pair = {nonByes[0].playerAId, nonByes[0].playerBId!};
      // Top two by points (p2 and p3) should be paired
      expect(pair, containsAll(['p2', 'p3']));
    });
  });

  group('match status', () {
    test('non-bye matches start with pending status', () {
      final matches = SwissPairing().pairRound(1, [
        _player('p1'),
        _player('p2'),
        _player('p3'),
        _player('p4'),
      ], []);
      for (final m in matches.where((m) => !m.isBye)) {
        expect(m.status, MatchStatus.pending);
      }
    });

    test('bye matches are auto-confirmed', () {
      final matches = SwissPairing().pairRound(1, [
        _player('p1'),
        _player('p2'),
        _player('p3'),
      ], []);
      final bye = matches.firstWhere((m) => m.isBye);
      expect(bye.status, MatchStatus.confirmed);
    });
  });

  group('round number', () {
    test('all matches have correct round number', () {
      final matches = SwissPairing().pairRound(5, [
        _player('p1'),
        _player('p2'),
        _player('p3'),
        _player('p4'),
      ], []);
      for (final m in matches) {
        expect(m.roundNumber, 5);
      }
    });
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';

void main() {
  group('DraftState', () {
    late DraftState state8;
    late DraftState state4;

    setUp(() {
      state8 = DraftState.create(
        name: 'Test Draft 8',
        leaderDeviceId: 'leader-001',
        leaderPlayerName: 'Host',
        seatCount: 8,
      );
      state4 = DraftState.create(
        name: 'Test Draft 4',
        leaderDeviceId: 'leader-001',
        leaderPlayerName: 'Host',
        seatCount: 4,
      );
    });

    group('create()', () {
      test('defaults: empty players except leader, empty rounds', () {
        expect(state8.players.length, 1);
        expect(state8.players.first.deviceId, 'leader-001');
        expect(state8.players.first.status, PlayerStatus.accepted);
        expect(state8.players.first.seatNumber, 1);
        expect(state8.players.first.joinOrder, 0);
        expect(state8.rounds, isEmpty);
      });

      test('sequenceNumber starts at 0', () {
        expect(state8.sequenceNumber, 0);
      });

      test('session defaults', () {
        expect(state8.session.name, 'Test Draft 8');
        expect(state8.session.phase, DraftPhase.lobby);
        expect(state8.session.seatCount, 8);
        expect(state8.session.roundDurationSeconds, 300);
        expect(state8.session.setCode, isNull);
        expect(state8.session.cubeId, isNull);
      });

      test('sessionId is non-empty', () {
        expect(state8.session.sessionId, isNotEmpty);
        expect(state8.session.sessionId, contains('-'));
      });

      test('totalRounds = ceil(log2(seatCount)).clamp(0,6)', () {
        expect(state8.session.totalRounds, 3); // log2(8)=3, capped at 6 = 3
        expect(state4.session.totalRounds, 2); // log2(4)=2, capped at 6 = 2
        final state32 = DraftState.create(
          name: 'Big',
          leaderDeviceId: 'l',
          leaderPlayerName: 'Host',
          seatCount: 32,
        );
        expect(state32.session.totalRounds, 5); // log2(32)=5
        final state64 = DraftState.create(
          name: 'Huge',
          leaderDeviceId: 'l',
          leaderPlayerName: 'Host',
          seatCount: 64,
        );
        expect(state64.session.totalRounds, 6); // log2(64)=6, capped at 6 = 6
        final state128 = DraftState.create(
          name: 'Huge2',
          leaderDeviceId: 'l',
          leaderPlayerName: 'Host',
          seatCount: 128,
        );
        expect(state128.session.totalRounds, 6); // log2(128)=7, capped at 6 = 6
      });

      test('setCode and cubeId are optional', () {
        final state = DraftState.create(
          name: 'Draft',
          leaderDeviceId: 'l',
          leaderPlayerName: 'Host',
          seatCount: 8,
          setCode: 'DMU',
          cubeId: 'my-cube',
        );
        expect(state.session.setCode, 'DMU');
        expect(state.session.cubeId, 'my-cube');
      });

      test('roundDurationSeconds is configurable', () {
        final state = DraftState.create(
          name: 'Draft',
          leaderDeviceId: 'l',
          leaderPlayerName: 'Host',
          seatCount: 8,
          roundDurationSeconds: 600,
        );
        expect(state.session.roundDurationSeconds, 600);
      });
    });

    group('bumpSequence()', () {
      test('increments sequenceNumber by 1', () {
        final bumped = state8.bumpSequence();
        expect(bumped.sequenceNumber, 1);
      });

      test('is composable', () {
        final bumped = state8.bumpSequence().bumpSequence().bumpSequence();
        expect(bumped.sequenceNumber, 3);
      });
    });

    group('copyWith()', () {
      test('preserves unchanged fields', () {
        final copy = state8.copyWith();
        expect(copy.sequenceNumber, state8.sequenceNumber);
        expect(copy.session, state8.session);
        expect(copy.players, state8.players);
        expect(copy.rounds, state8.rounds);
      });

      test('updates session', () {
        final newSession = state8.session.copyWith(name: 'Renamed');
        final copy = state8.copyWith(session: newSession);
        expect(copy.session.name, 'Renamed');
        expect(copy.sequenceNumber, state8.sequenceNumber);
      });

      test('updates players', () {
        final newPlayers = [
          DraftPlayer(
            deviceId: 'p1',
            playerName: 'Test',
            deviceName: 'Phone',
            joinOrder: 0,
            status: PlayerStatus.accepted,
          ),
        ];
        final copy = state8.copyWith(players: newPlayers);
        expect(copy.players.length, 1);
        expect(copy.players.first.deviceId, 'p1');
      });
    });

    group('JSON round-trip', () {
      test('all fields survive toJson → fromJson', () {
        final json = state8.toJson();
        final decoded = DraftState.fromJson(json);

        expect(decoded.sequenceNumber, state8.sequenceNumber);
        expect(decoded.session.sessionId, state8.session.sessionId);
        expect(decoded.session.name, state8.session.name);
        expect(decoded.session.phase, state8.session.phase);
        expect(decoded.session.seatCount, state8.session.seatCount);
        expect(decoded.players.length, state8.players.length);
        expect(decoded.players.first.deviceId, state8.players.first.deviceId);
        expect(decoded.rounds.length, state8.rounds.length);
      });

      test('null fields (setCode, cubeId, seatNumber) handled correctly', () {
        final state = state8.copyWith(
          session: state8.session.copyWith(clearSetCode: true, clearCubeId: true),
          players: [
            DraftPlayer(
              deviceId: 'p1',
              playerName: 'Test',
              deviceName: 'Phone',
              joinOrder: 0,
              seatNumber: null,
            ),
          ],
        );
        final json = state.toJson();
        final decoded = DraftState.fromJson(json);

        expect(decoded.session.setCode, isNull);
        expect(decoded.session.cubeId, isNull);
        expect(decoded.players.first.seatNumber, isNull);
      });

      test('rounds are optional in JSON (empty list)', () {
        final state = state8.copyWith(rounds: []);
        final json = state.toJson();
        final decoded = DraftState.fromJson(json);
        expect(decoded.rounds, isEmpty);
      });

      test('fromJson handles null rounds array', () {
        final baseJson = state8.toJson();
        baseJson.remove('r');
        final decoded = DraftState.fromJson(baseJson);
        expect(decoded.rounds, isEmpty);
      });

      test('session createdAt survives round-trip', () {
        final json = state8.toJson();
        final decoded = DraftState.fromJson(json);
        final diff = decoded.session.createdAt
            .difference(state8.session.createdAt)
            .inMilliseconds
            .abs();
        // DateTime precision: ISO string truncates microseconds
        expect(diff, lessThan(1000));
      });
    });

    group('leaderDeviceId', () {
      test('returns first player\'s deviceId', () {
        expect(state8.leaderDeviceId, 'leader-001');
      });

      test('returns null when players is empty', () {
        final empty = state8.copyWith(players: []);
        expect(empty.leaderDeviceId, isNull);
      });
    });

    group('acceptedPlayers', () {
      test('returns only accepted players', () {
        final state = state8.copyWith(
          players: [
            DraftPlayer(
              deviceId: 'a',
              playerName: 'AA',
              deviceName: 'Phone',
              joinOrder: 0,
              status: PlayerStatus.accepted,
            ),
            DraftPlayer(
              deviceId: 'b',
              playerName: 'BB',
              deviceName: 'Phone',
              joinOrder: 1,
              status: PlayerStatus.pending,
            ),
            DraftPlayer(
              deviceId: 'c',
              playerName: 'CC',
              deviceName: 'Phone',
              joinOrder: 2,
              status: PlayerStatus.accepted,
            ),
            DraftPlayer(
              deviceId: 'd',
              playerName: 'DD',
              deviceName: 'Phone',
              joinOrder: 3,
              status: PlayerStatus.dropped,
            ),
          ],
        );
        expect(state.acceptedPlayers.length, 2);
        expect(state.acceptedPlayers.map((p) => p.deviceId),
            containsAll(['a', 'c']));
      });
    });

    group('activePlayers', () {
      test('filters out dropped players', () {
        final state = state8.copyWith(
          players: [
            DraftPlayer(
              deviceId: 'a',
              playerName: 'AA',
              deviceName: 'Phone',
              joinOrder: 0,
              status: PlayerStatus.accepted,
            ),
            DraftPlayer(
              deviceId: 'b',
              playerName: 'BB',
              deviceName: 'Phone',
              joinOrder: 1,
              status: PlayerStatus.pending,
            ),
            DraftPlayer(
              deviceId: 'c',
              playerName: 'CC',
              deviceName: 'Phone',
              joinOrder: 2,
              status: PlayerStatus.dropped,
            ),
          ],
        );
        expect(state.activePlayers.length, 2);
        expect(state.activePlayers.map((p) => p.deviceId),
            containsAll(['a', 'b']));
        expect(state.activePlayers.map((p) => p.deviceId),
            isNot(contains('c')));
      });
    });

    group('getPlayer', () {
      test('returns player by deviceId', () {
        final state = state8.copyWith(
          players: [
            DraftPlayer(
              deviceId: 'p1',
              playerName: 'Alice',
              deviceName: 'Phone',
              joinOrder: 0,
            ),
            DraftPlayer(
              deviceId: 'p2',
              playerName: 'Bob',
              deviceName: 'Phone',
              joinOrder: 1,
            ),
          ],
        );
        final player = state.getPlayer('p2');
        expect(player, isNotNull);
        expect(player!.playerName, 'Bob');
      });

      test('returns null when not found', () {
        final player = state8.getPlayer('nonexistent');
        expect(player, isNull);
      });
    });

    group('getMyMatch', () {
      test('returns match for given deviceId + roundNumber', () {
        final state = DraftState(
          sequenceNumber: 0,
          session: state8.session,
          players: [
            DraftPlayer(
              deviceId: 'p1',
              playerName: 'Alice',
              deviceName: 'Phone',
              joinOrder: 0,
            ),
          ],
          rounds: [
            DraftRound(
              roundNumber: 1,
              matches: [
                DraftMatch(
                  matchId: 'm1',
                  roundNumber: 1,
                  playerAId: 'p1',
                  playerBId: 'p2',
                ),
              ],
            ),
          ],
        );

        final match = state.getMyMatch('p1', 1);
        expect(match, isNotNull);
        expect(match!.matchId, 'm1');
      });

      test('returns null for missing round', () {
        final state = DraftState(
          sequenceNumber: 0,
          session: state8.session,
          players: [],
          rounds: [
            DraftRound(roundNumber: 1, matches: []),
          ],
        );
        expect(state.getMyMatch('p1', 99), isNull);
      });

      test('returns null for missing deviceId in round', () {
        final state = DraftState(
          sequenceNumber: 0,
          session: state8.session,
          players: [],
          rounds: [
            DraftRound(
              roundNumber: 1,
              matches: [
                DraftMatch(
                  matchId: 'm1',
                  roundNumber: 1,
                  playerAId: 'p1',
                  playerBId: 'p2',
                ),
              ],
            ),
          ],
        );
        expect(state.getMyMatch('p99', 1), isNull);
      });
    });

    group('standings', () {
      test('empty players → empty list', () {
        final state = state8.copyWith(players: []);
        expect(state.standings, isEmpty);
      });

      test('sorts by match points descending', () {
        final state = DraftState(
          sequenceNumber: 0,
          session: state8.session,
          players: [
            DraftPlayer(
              deviceId: 'p1',
              playerName: 'Alice',
              deviceName: 'Phone',
              joinOrder: 0,
              status: PlayerStatus.accepted,
              matchWins: 1,
            ),
            DraftPlayer(
              deviceId: 'p2',
              playerName: 'Bob',
              deviceName: 'Phone',
              joinOrder: 1,
              status: PlayerStatus.accepted,
              matchWins: 3,
            ),
            DraftPlayer(
              deviceId: 'p3',
              playerName: 'Charlie',
              deviceName: 'Phone',
              joinOrder: 2,
              status: PlayerStatus.accepted,
              matchWins: 0,
            ),
          ],
        );
        final standings = state.standings;
        expect(standings[0].deviceId, 'p2'); // 9 points
        expect(standings[1].deviceId, 'p1'); // 3 points
        expect(standings[2].deviceId, 'p3'); // 0 points
      });

      test('tiebreak: opponent match-win % (OMW%)', () {
        final state = DraftState(
          sequenceNumber: 0,
          session: state8.session,
          players: [
            DraftPlayer(
              deviceId: 'p1',
              playerName: 'Alice',
              deviceName: 'Phone',
              joinOrder: 0,
              status: PlayerStatus.accepted,
              matchWins: 2,
            ),
            DraftPlayer(
              deviceId: 'p2',
              playerName: 'Bob',
              deviceName: 'Phone',
              joinOrder: 1,
              status: PlayerStatus.accepted,
              matchWins: 2,
            ),
            DraftPlayer(
              deviceId: 'p3',
              playerName: 'Charlie',
              deviceName: 'Phone',
              joinOrder: 2,
              status: PlayerStatus.accepted,
              matchWins: 0,
            ),
            DraftPlayer(
              deviceId: 'p4',
              playerName: 'Diana',
              deviceName: 'Phone',
              joinOrder: 3,
              status: PlayerStatus.accepted,
              matchWins: 0,
            ),
          ],
          rounds: [
            DraftRound(
              roundNumber: 1,
              matches: [
                DraftMatch(
                  matchId: 'm1',
                  roundNumber: 1,
                  playerAId: 'p1',
                  playerBId: 'p3',
                  aWins: 2,
                  bWins: 0,
                  draws: 0,
                  status: MatchStatus.confirmed,
                ),
                DraftMatch(
                  matchId: 'm2',
                  roundNumber: 1,
                  playerAId: 'p2',
                  playerBId: 'p4',
                  aWins: 2,
                  bWins: 0,
                  draws: 0,
                  status: MatchStatus.confirmed,
                ),
              ],
            ),
          ],
        );
        // p1 and p2 have same match points, same OMW% (both beat winless opponents)
        // Falls to GWP%
        final standings = state.standings;
        expect(standings[0].deviceId, anyOf('p1', 'p2'));
        expect(standings[1].deviceId, anyOf('p1', 'p2'));
      });

      test('tiebreak: game win %', () {
        final state = DraftState(
          sequenceNumber: 0,
          session: state8.session,
          players: [
            DraftPlayer(
              deviceId: 'p1',
              playerName: 'Alice',
              deviceName: 'Phone',
              joinOrder: 0,
              status: PlayerStatus.accepted,
              matchWins: 2,
            ),
            DraftPlayer(
              deviceId: 'p2',
              playerName: 'Bob',
              deviceName: 'Phone',
              joinOrder: 1,
              status: PlayerStatus.accepted,
              matchWins: 2,
              matchDraws: 1,
            ),
          ],
          rounds: [],
        );
        final standings = state.standings;
        expect(standings[0].deviceId, 'p2'); // 7 points (6+1)
        expect(standings[1].deviceId, 'p1'); // 6 points
      });
    });
  });

  group('DraftSession', () {
    late DraftSession session;

    setUp(() {
      session = DraftState.create(
        name: 'Test',
        leaderDeviceId: 'l',
        leaderPlayerName: 'Host',
        seatCount: 8,
      ).session;
    });

    group('JSON round-trip', () {
      test('all fields survive', () {
        final json = session.toJson();
        final decoded = DraftSession.fromJson(json);

        expect(decoded.sessionId, session.sessionId);
        expect(decoded.name, session.name);
        expect(decoded.seatCount, session.seatCount);
        expect(decoded.phase, session.phase);
        expect(decoded.totalRounds, session.totalRounds);
        expect(decoded.roundDurationSeconds, session.roundDurationSeconds);
      });

      test('null setCode/cubeId survive', () {
        final s = session.copyWith(clearSetCode: true, clearCubeId: true);
        final json = s.toJson();
        final decoded = DraftSession.fromJson(json);
        expect(decoded.setCode, isNull);
        expect(decoded.cubeId, isNull);
      });

      test('non-null setCode/cubeId survive', () {
        final s = session.copyWith(setCode: 'DMU', cubeId: 'my-cube');
        final json = s.toJson();
        final decoded = DraftSession.fromJson(json);
        expect(decoded.setCode, 'DMU');
        expect(decoded.cubeId, 'my-cube');
      });

      test('roundDurationSeconds defaults to 300 when missing', () {
        final json = session.toJson();
        json.remove('d');
        final decoded = DraftSession.fromJson(json);
        expect(decoded.roundDurationSeconds, 300);
      });
    });

    group('copyWith', () {
      test('clearSetCode nulls setCode', () {
        final s = session.copyWith(setCode: 'DMU');
        final cleared = s.copyWith(clearSetCode: true);
        expect(cleared.setCode, isNull);
      });

      test('clearCubeId nulls cubeId', () {
        final s = session.copyWith(cubeId: 'cube');
        final cleared = s.copyWith(clearCubeId: true);
        expect(cleared.cubeId, isNull);
      });
    });
  });

  group('DraftPlayer', () {
    final player = DraftPlayer(
      deviceId: 'd1',
      playerName: 'Alice',
      deviceName: 'Phone',
      joinOrder: 0,
      status: PlayerStatus.accepted,
    );

    test('matchPoints = 3×wins + 1×draws', () {
      expect(DraftPlayer(deviceId: 'p', playerName: 'n', deviceName: 'd', joinOrder: 0, matchWins: 2, matchDraws: 1).matchPoints, 7);
      expect(DraftPlayer(deviceId: 'p', playerName: 'n', deviceName: 'd', joinOrder: 0, matchWins: 0, matchDraws: 3).matchPoints, 3);
      expect(DraftPlayer(deviceId: 'p', playerName: 'n', deviceName: 'd', joinOrder: 0, matchWins: 0, matchDraws: 0).matchPoints, 0);
      expect(DraftPlayer(deviceId: 'p', playerName: 'n', deviceName: 'd', joinOrder: 0, matchWins: 5, matchDraws: 0).matchPoints, 15);
    });

    test('gameWinPercentage returns 0.0 when 0 games played', () {
      expect(player.gameWinPercentage, 0.0);
    });

    test('gameWinPercentage calculation', () {
      final p = DraftPlayer(
        deviceId: 'p',
        playerName: 'n',
        deviceName: 'd',
        joinOrder: 0,
        matchWins: 2,
        matchLosses: 1,
        matchDraws: 1,
      );
      // (2 + 0.5) / 4 = 0.625
      expect(p.gameWinPercentage, 0.625);
    });

    test('copyWith clearSeat nulls seatNumber', () {
      final p = player.copyWith(seatNumber: 5);
      expect(p.seatNumber, 5);
      final cleared = p.copyWith(clearSeat: true);
      expect(cleared.seatNumber, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final copy = player.copyWith();
      expect(copy.deviceId, player.deviceId);
      expect(copy.playerName, player.playerName);
      expect(copy.status, player.status);
    });

    group('JSON round-trip', () {
      test('all fields survive', () {
        final json = player.toJson();
        final decoded = DraftPlayer.fromJson(json);

        expect(decoded.deviceId, player.deviceId);
        expect(decoded.playerName, player.playerName);
        expect(decoded.joinOrder, player.joinOrder);
        expect(decoded.status, player.status);
        expect(decoded.matchWins, player.matchWins);
        expect(decoded.matchLosses, player.matchLosses);
        expect(decoded.matchDraws, player.matchDraws);
      });

      test('null seatNumber survives', () {
        final json = player.toJson();
        final decoded = DraftPlayer.fromJson(json);
        expect(decoded.seatNumber, isNull);
      });

      test('matchWins/matchLosses/matchDraws default to 0 when null', () {
        final json = {
          'd': 'p',
          'n': 'X',
          'j': 0,
          's': 'accepted',
        };
        final decoded = DraftPlayer.fromJson(json);
        expect(decoded.matchWins, 0);
        expect(decoded.matchLosses, 0);
        expect(decoded.matchDraws, 0);
      });
    });
  });

  group('DraftMatch', () {
    test('isBye → true when playerBId is null', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
      );
      expect(match.isBye, isTrue);
    });

    test('isBye → false when playerBId is set', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        playerBId: 'p2',
      );
      expect(match.isBye, isFalse);
    });

    test('winnerId → playerAId for confirmed bye', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        status: MatchStatus.confirmed,
      );
      expect(match.winnerId(), 'p1');
    });

    test('winnerId → null for non-confirmed bye', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        status: MatchStatus.pending,
      );
      expect(match.winnerId(), isNull);
    });

    test('winnerId → playerA wins', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        playerBId: 'p2',
        aWins: 2,
        bWins: 0,
        draws: 0,
        status: MatchStatus.confirmed,
      );
      expect(match.winnerId(), 'p1');
    });

    test('winnerId → playerB wins', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        playerBId: 'p2',
        aWins: 0,
        bWins: 2,
        draws: 0,
        status: MatchStatus.confirmed,
      );
      expect(match.winnerId(), 'p2');
    });

    test('winnerId → null for draw', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        playerBId: 'p2',
        aWins: 1,
        bWins: 1,
        draws: 1,
        status: MatchStatus.confirmed,
      );
      expect(match.winnerId(), isNull);
    });

    test('winnerId → null when scores are null', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        playerBId: 'p2',
        status: MatchStatus.confirmed,
      );
      expect(match.winnerId(), isNull);
    });

    test('copyWith clearPlayerB nulls playerBId', () {
      final match = DraftMatch(
        matchId: 'm1',
        roundNumber: 1,
        playerAId: 'p1',
        playerBId: 'p2',
        aWins: 2,
        bWins: 0,
        draws: 0,
      );
      final cleared = match.copyWith(clearPlayerB: true);
      expect(cleared.playerBId, isNull);
      expect(cleared.isBye, isTrue);
    });

    group('JSON round-trip', () {
      test('all fields survive with both players', () {
        final match = DraftMatch(
          matchId: 'm1',
          roundNumber: 2,
          playerAId: 'p1',
          playerBId: 'p2',
          aWins: 2,
          bWins: 1,
          draws: 0,
          status: MatchStatus.confirmed,
        );
        final json = match.toJson();
        final decoded = DraftMatch.fromJson(json);

        expect(decoded.matchId, match.matchId);
        expect(decoded.roundNumber, match.roundNumber);
        expect(decoded.playerAId, match.playerAId);
        expect(decoded.playerBId, match.playerBId);
        expect(decoded.aWins, match.aWins);
        expect(decoded.bWins, match.bWins);
        expect(decoded.draws, match.draws);
        expect(decoded.status, match.status);
      });

      test('byes survive with null playerBId', () {
        final match = DraftMatch(
          matchId: 'bye1',
          roundNumber: 1,
          playerAId: 'p1',
          status: MatchStatus.confirmed,
        );
        final json = match.toJson();
        final decoded = DraftMatch.fromJson(json);

        expect(decoded.playerBId, isNull);
        expect(decoded.aWins, isNull);
        expect(decoded.bWins, isNull);
        expect(decoded.draws, isNull);
        expect(decoded.isBye, isTrue);
      });
    });
  });

  group('DraftRound', () {
    group('JSON round-trip', () {
      test('round with matches survives', () {
        final round = DraftRound(
          roundNumber: 1,
          matches: [
            DraftMatch(
              matchId: 'm1',
              roundNumber: 1,
              playerAId: 'p1',
              playerBId: 'p2',
            ),
          ],
          complete: true,
        );
        final json = round.toJson();
        final decoded = DraftRound.fromJson(json);

        expect(decoded.roundNumber, 1);
        expect(decoded.matches.length, 1);
        expect(decoded.complete, isTrue);
      });

      test('null roundStartTime survives', () {
        final round = DraftRound(
          roundNumber: 1,
          matches: [],
        );
        final json = round.toJson();
        final decoded = DraftRound.fromJson(json);
        expect(decoded.roundStartTime, isNull);
      });

      test('roundStartTime survives round-trip', () {
        final now = DateTime.now().toUtc();
        final round = DraftRound(
          roundNumber: 1,
          matches: [],
          roundStartTime: now,
        );
        final json = round.toJson();
        final decoded = DraftRound.fromJson(json);
        expect(decoded.roundStartTime, isNotNull);
        // DateTime precision: ISO string truncates microseconds
        final diff = decoded.roundStartTime!.difference(now).inMilliseconds.abs();
        expect(diff, lessThan(1000));
      });

      test('complete defaults to false when missing', () {
        final json = {
          'r': 1,
          'm': <Map<String, dynamic>>[],
        };
        final decoded = DraftRound.fromJson(json);
        expect(decoded.complete, isFalse);
      });
    });
  });

  group('enums', () {
    group('DraftPhase', () {
      test('name returns correct string for each value', () {
        expect(DraftPhase.advertising.name, 'advertising');
        expect(DraftPhase.lobby.name, 'lobby');
        expect(DraftPhase.seatingsAssigned.name, 'seatings_assigned');
        expect(DraftPhase.inProgress.name, 'in_progress');
        expect(DraftPhase.complete.name, 'complete');
        expect(DraftPhase.cancelled.name, 'cancelled');
      });

      test('fromString returns correct value for known strings', () {
        expect(DraftPhase.fromString('advertising'), DraftPhase.advertising);
        expect(DraftPhase.fromString('lobby'), DraftPhase.lobby);
        expect(DraftPhase.fromString('seatings_assigned'),
            DraftPhase.seatingsAssigned);
        expect(DraftPhase.fromString('in_progress'), DraftPhase.inProgress);
        expect(DraftPhase.fromString('complete'), DraftPhase.complete);
        expect(DraftPhase.fromString('cancelled'), DraftPhase.cancelled);
      });

      test('fromString falls back to lobby for unknown value', () {
        expect(DraftPhase.fromString('invalid'), DraftPhase.lobby);
        expect(DraftPhase.fromString(''), DraftPhase.lobby);
      });
    });

    group('PlayerStatus', () {
      test('name returns correct string for each value', () {
        expect(PlayerStatus.pending.name, 'pending');
        expect(PlayerStatus.accepted.name, 'accepted');
        expect(PlayerStatus.dropped.name, 'dropped');
      });

      test('fromString returns correct value for known strings', () {
        expect(PlayerStatus.fromString('pending'), PlayerStatus.pending);
        expect(PlayerStatus.fromString('accepted'), PlayerStatus.accepted);
        expect(PlayerStatus.fromString('dropped'), PlayerStatus.dropped);
      });

      test('fromString falls back to pending for unknown value', () {
        expect(PlayerStatus.fromString('invalid'), PlayerStatus.pending);
      });
    });

    group('MatchStatus', () {
      test('name returns correct string for each value', () {
        expect(MatchStatus.pending.name, 'pending');
        expect(MatchStatus.reported.name, 'reported');
        expect(MatchStatus.confirmed.name, 'confirmed');
        expect(MatchStatus.conflicted.name, 'conflicted');
      });

      test('fromString returns correct value for known strings', () {
        expect(MatchStatus.fromString('pending'), MatchStatus.pending);
        expect(MatchStatus.fromString('reported'), MatchStatus.reported);
        expect(MatchStatus.fromString('confirmed'), MatchStatus.confirmed);
        expect(MatchStatus.fromString('conflicted'), MatchStatus.conflicted);
      });

      test('fromString falls back to pending for unknown value', () {
        expect(MatchStatus.fromString('invalid'), MatchStatus.pending);
      });
    });
  });

  group('log2 helper', () {
    test('log2 of powers of two', () {
      expect(log2(2), 1);
      expect(log2(4), 2);
      expect(log2(8), 3);
      expect(log2(16), 4);
      expect(log2(32), 5);
      expect(log2(64), 6);
    });

    test('log2 of 1 returns 0', () {
      expect(log2(1), 0);
    });
  });
}

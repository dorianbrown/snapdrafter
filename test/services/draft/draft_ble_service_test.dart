import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';

void main() {
  group('DraftBleService', () {
    late DraftState testState;

    setUp(() {
      testState = DraftState.create(
        name: 'Test Draft',
        leaderDeviceId: 'leader-001',
        seatCount: 8,
        setCode: 'DMU',
      );
    });

    group('encodeState / decodeState', () {
      test('round-trip preserves all fields', () {
        final encoded = DraftBleService.encodeState(testState);
        final decoded = DraftBleService.decodeState(encoded);
        expect(decoded, isNotNull);

        expect(decoded!.sequenceNumber, testState.sequenceNumber);
        expect(decoded.session.name, testState.session.name);
        expect(decoded.session.sessionId, testState.session.sessionId);
        expect(decoded.session.seatCount, testState.session.seatCount);
        expect(decoded.session.phase, testState.session.phase);
        expect(decoded.session.setCode, testState.session.setCode);
        expect(decoded.players.length, testState.players.length);
        expect(decoded.players.first.deviceId, testState.players.first.deviceId);
        expect(decoded.rounds.length, testState.rounds.length);
      });

      test('round-trip with players and rounds', () {
        final state = testState.copyWith(
          players: [
            ...testState.players,
            DraftPlayer(
              deviceId: 'follower-1',
              playerName: 'Alice',
              deviceName: 'Pixel 7',
              joinOrder: 1,
              status: PlayerStatus.accepted,
            ),
          ],
          rounds: [
            DraftRound(
              roundNumber: 1,
              matches: [
                DraftMatch(
                  matchId: 'm1',
                  roundNumber: 1,
                  playerAId: 'leader-001',
                  playerBId: 'follower-1',
                ),
              ],
            ),
          ],
        );

        final encoded = DraftBleService.encodeState(state);
        final decoded = DraftBleService.decodeState(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.players.length, 2);
        expect(decoded.rounds.length, 1);
        expect(decoded.rounds.first.matches.length, 1);
      });

      test('round-trip with nullable fields set', () {
        final state = testState.copyWith(
          session: testState.session.copyWith(
            setCode: 'DMU',
            cubeId: 'my-cube',
          ),
        );

        final encoded = DraftBleService.encodeState(state);
        final decoded = DraftBleService.decodeState(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.session.setCode, 'DMU');
        expect(decoded.session.cubeId, 'my-cube');
      });

      test('round-trip with nullable fields null', () {
        final state = testState.copyWith(
          session: testState.session.copyWith(
            clearSetCode: true,
            clearCubeId: true,
          ),
        );

        final encoded = DraftBleService.encodeState(state);
        final decoded = DraftBleService.decodeState(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.session.setCode, isNull);
        expect(decoded.session.cubeId, isNull);
      });

      test('round-trip with cancelled phase', () {
        final state = testState.copyWith(
          session: testState.session.copyWith(phase: DraftPhase.cancelled),
        );

        final encoded = DraftBleService.encodeState(state);
        final decoded = DraftBleService.decodeState(encoded);
        expect(decoded, isNotNull);
        expect(decoded!.session.phase, DraftPhase.cancelled);
      });
    });

    group('encodeMeta', () {
      test('encodes session metadata as valid JSON', () {
        final encoded = DraftBleService.encodeMeta(testState.session);
        final json = utf8.decode(encoded);
        final map = jsonDecode(json) as Map<String, dynamic>;

        expect(map['n'], 'Test Draft');
        expect(map['i'], testState.session.sessionId);
        expect(map['k'], 8);
        expect(map['h'], 'lobby');
      });
    });

    group('decodeState error handling', () {
      test('returns null for corrupt bytes', () {
        final corrupt = Uint8List.fromList([0xFF, 0xFE, 0xFD, 0x00, 0x01]);
        final result = DraftBleService.decodeState(corrupt);
        expect(result, isNull);
      });

      test('returns null for truncated JSON', () {
        final fullJson = utf8.encode('{"sequenceNumber":0,"session":{');
        final truncated = Uint8List.fromList(fullJson);
        final result = DraftBleService.decodeState(truncated);
        expect(result, isNull);
      });

      test('returns null for empty bytes', () {
        final result = DraftBleService.decodeState(Uint8List(0));
        expect(result, isNull);
      });

      test('returns null for valid JSON that is not a DraftState', () {
        final badJson = Uint8List.fromList(utf8.encode('{"foo":"bar"}'));
        final result = DraftBleService.decodeState(badJson);
        expect(result, isNull);
      });
    });

    group('UUID constants', () {
      test('service, meta, state, command UUIDs are distinct', () {
        expect(DraftBleService.serviceUuid, isNot(DraftBleService.metaCharUuid));
        expect(DraftBleService.serviceUuid, isNot(DraftBleService.stateCharUuid));
        expect(DraftBleService.serviceUuid, isNot(DraftBleService.commandCharUuid));
        expect(DraftBleService.metaCharUuid, isNot(DraftBleService.stateCharUuid));
        expect(DraftBleService.stateCharUuid, isNot(DraftBleService.commandCharUuid));
      });
    });
  });
}

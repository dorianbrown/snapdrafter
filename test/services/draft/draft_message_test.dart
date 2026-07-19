import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/draft_message.dart';

void main() {
  group('DraftCommand', () {
    group('JoinRequest', () {
      test('toJson → fromJson round-trip', () {
        final original = JoinRequest(
          playerName: 'Alice',
          deviceName: 'Pixel 7',
        );
        final json = original.toJson();
        final decoded = JoinRequest.fromJson(json);

        expect(decoded.playerName, 'Alice');
        expect(decoded.deviceName, 'Pixel 7');
        expect(decoded.type, DraftCommandType.joinRequest);
      });

      test('fromJson via DraftCommand.fromJson dispatches correctly', () {
        final json = {
          'type': 'join_request',
          'playerName': 'Bob',
          'deviceName': 'Galaxy S24',
        };
        final cmd = DraftCommand.fromJson(json);
        expect(cmd, isA<JoinRequest>());
        final join = cmd as JoinRequest;
        expect(join.playerName, 'Bob');
        expect(join.deviceName, 'Galaxy S24');
      });

      test('toJson includes type field', () {
        final join = JoinRequest(playerName: 'Test', deviceName: 'TestDevice');
        final json = join.toJson();
        expect(json['type'], 'join_request');
      });
    });

    group('MatchResult', () {
      test('toJson → fromJson round-trip', () {
        final original = MatchResult(
          roundNumber: 2,
          matchId: 'match-abc',
          myWins: 2,
          opponentWins: 1,
        );
        final json = original.toJson();
        final decoded = MatchResult.fromJson(json);

        expect(decoded.roundNumber, 2);
        expect(decoded.matchId, 'match-abc');
        expect(decoded.myWins, 2);
        expect(decoded.opponentWins, 1);
        expect(decoded.type, DraftCommandType.matchResult);
      });

      test('fromJson via DraftCommand.fromJson dispatches correctly', () {
        final json = {
          'type': 'match_result',
          'roundNumber': 1,
          'matchId': 'm1',
          'myWins': 1,
          'opponentWins': 2,
          
        };
        final cmd = DraftCommand.fromJson(json);
        expect(cmd, isA<MatchResult>());
        final result = cmd as MatchResult;
        expect(result.roundNumber, 1);
        expect(result.matchId, 'm1');
        expect(result.myWins, 1);
        expect(result.opponentWins, 2);
      });

      test('toJson includes type field', () {
        final result = MatchResult(
          roundNumber: 1,
          matchId: 'm1',
          myWins: 2,
          opponentWins: 0,
        );
        final json = result.toJson();
        expect(json['type'], 'match_result');
      });
    });

    group('DropRequest', () {
      test('toJson → fromJson round-trip', () {
        final original = DropRequest();
        final json = original.toJson();
        final decoded = DropRequest.fromJson(json);

        expect(decoded.type, DraftCommandType.dropRequest);
      });

      test('fromJson via DraftCommand.fromJson dispatches correctly', () {
        final cmd = DraftCommand.fromJson({'type': 'drop_request'});
        expect(cmd, isA<DropRequest>());
        expect(cmd.type, DraftCommandType.dropRequest);
      });

      test('toJson includes type field', () {
        final drop = DropRequest();
        final json = drop.toJson();
        expect(json['type'], 'drop_request');
      });
    });

    group('DraftCommand.fromJson unknown type', () {
      test('falls back to JoinRequest for unknown type string', () {
        final cmd = DraftCommand.fromJson({
          'type': 'unknown_command_type',
          'playerName': '',
          'deviceName': '',
        });
        expect(cmd, isA<JoinRequest>());
      });
    });

    group('DraftCommandType.enum', () {
      test('name returns correct string for each value', () {
        expect(DraftCommandType.joinRequest.name, 'join_request');
        expect(DraftCommandType.matchResult.name, 'match_result');
        expect(DraftCommandType.dropRequest.name, 'drop_request');
        expect(DraftCommandType.submitDecklist.name, 'submit_decklist');
      });

      test('fromString returns correct value for known strings', () {
        expect(DraftCommandType.fromString('join_request'),
            DraftCommandType.joinRequest);
        expect(DraftCommandType.fromString('match_result'),
            DraftCommandType.matchResult);
        expect(DraftCommandType.fromString('drop_request'),
            DraftCommandType.dropRequest);
        expect(DraftCommandType.fromString('submit_decklist'),
            DraftCommandType.submitDecklist);
      });

      test('fromString falls back to joinRequest for unknown string', () {
        expect(DraftCommandType.fromString('unknown'),
            DraftCommandType.joinRequest);
        expect(DraftCommandType.fromString(''), DraftCommandType.joinRequest);
      });
    });

    group('SubmitDecklist', () {
      test('toJson → fromJson round-trip', () {
        final original = SubmitDecklist(
          mainboardScryfallIds: ['id-1', 'id-2', 'id-3'],
          sideboardScryfallIds: ['id-side-1'],
        );
        final json = original.toJson();
        final decoded = SubmitDecklist.fromJson(json);

        expect(decoded.mainboardScryfallIds, ['id-1', 'id-2', 'id-3']);
        expect(decoded.sideboardScryfallIds, ['id-side-1']);
        expect(decoded.type, DraftCommandType.submitDecklist);
      });

      test('fromJson via DraftCommand.fromJson dispatches correctly', () {
        final json = {
          'type': 'submit_decklist',
          'mb': ['a', 'b'],
          'sb': ['c'],
        };
        final cmd = DraftCommand.fromJson(json);
        expect(cmd, isA<SubmitDecklist>());
        final decklist = cmd as SubmitDecklist;
        expect(decklist.mainboardScryfallIds, ['a', 'b']);
        expect(decklist.sideboardScryfallIds, ['c']);
      });

      test('toJson includes type field', () {
        final cmd = SubmitDecklist(
          mainboardScryfallIds: ['x'],
          sideboardScryfallIds: [],
        );
        final json = cmd.toJson();
        expect(json['type'], 'submit_decklist');
        expect(json['mb'], ['x']);
        expect(json['sb'], []);
      });

      test('empty lists round-trip', () {
        final original = SubmitDecklist(
          mainboardScryfallIds: [],
          sideboardScryfallIds: [],
        );
        final json = original.toJson();
        final decoded = SubmitDecklist.fromJson(json);

        expect(decoded.mainboardScryfallIds, isEmpty);
        expect(decoded.sideboardScryfallIds, isEmpty);
      });
    });
  });
}

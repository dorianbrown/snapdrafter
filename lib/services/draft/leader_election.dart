import 'dart:async';
import 'draft_state.dart';
import 'draft_ble_follower.dart';
import 'draft_ble_leader.dart';

sealed class ElectionResult {
  const ElectionResult();
}

class FollowNewLeader extends ElectionResult {
  final String leaderDeviceId;
  const FollowNewLeader(this.leaderDeviceId);
}

class PromotedToLeader extends ElectionResult {
  final DraftBleLeader leader;
  const PromotedToLeader(this.leader);
}

class WaitForLeader extends ElectionResult {
  const WaitForLeader();
}

class LeaderElection {
  Future<ElectionResult> handleLeaderLost({
    required DraftState lastKnownState,
    required String myDeviceId,
    required DraftBleFollower currentFollower,
    required DraftBleLeader Function() createLeader,
  }) async {
    await Future.delayed(const Duration(seconds: 3));

    final tempScanner = DraftBleFollower();
    DiscoveredDraft? sameSessionDraft;

    try {
      final stream = tempScanner.scanForDrafts();
      await for (final draft in stream.timeout(
        const Duration(seconds: 2),
        onTimeout: (sink) => sink.close(),
      )) {
        if (draft.sessionId == lastKnownState.session.sessionId ||
            draft.draftName == lastKnownState.session.name) {
          sameSessionDraft = draft;
          break;
        }
      }
    } catch (_) {
    } finally {
      await tempScanner.stopScan();
      await tempScanner.stop();
    }

    if (sameSessionDraft != null &&
        sameSessionDraft.deviceId != myDeviceId) {
      return FollowNewLeader(sameSessionDraft.deviceId);
    }

    final eligible = lastKnownState.players
        .where((p) =>
            p.status == PlayerStatus.accepted ||
            p.status == PlayerStatus.pending)
        .toList()
      ..sort((a, b) => a.joinOrder.compareTo(b.joinOrder));

    if (eligible.isEmpty) {
      return const WaitForLeader();
    }

    if (eligible.first.deviceId != myDeviceId) {
      return const WaitForLeader();
    }

    await currentFollower.stop();

    final promotedState = _promoteState(lastKnownState, myDeviceId);
    final leader = createLeader();
    await leader.startAsLeader(promotedState);

    return PromotedToLeader(leader);
  }

  DraftState _promoteState(DraftState state, String newLeaderDeviceId) {
    final reorderedPlayers = <DraftPlayer>[];

    final newLeader = state.players.firstWhere(
      (p) => p.deviceId == newLeaderDeviceId,
    );

    reorderedPlayers.add(newLeader.copyWith(joinOrder: 0));

    var order = 1;
    for (final player in state.players) {
      if (player.deviceId == newLeaderDeviceId) continue;
      reorderedPlayers.add(player.copyWith(joinOrder: order++));
    }

    return state.copyWith(
      players: reorderedPlayers,
      sequenceNumber: state.sequenceNumber + 1,
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ble_platform.dart';
import 'draft_ble_follower.dart';
import 'draft_ble_leader.dart';
import 'draft_message.dart';
import 'draft_protocol.dart';
import 'draft_state.dart';

/// Relay node: a follower that also serves state to its own children.
///
/// Composition of the existing roles:
///   - [DraftBleLeader] (peripheral server) broadcasts snapshots and ticks to
///     direct children and tracks their ACKs.
///   - [DraftBleFollower] (central) keeps the parent link.
///
/// Player commands from children are forwarded upstream untouched; the `src`
/// field inside each command identifies the originating player. Decklist
/// requests are remembered so the bulk response can be routed back to the
/// child that asked.
class DraftRelayService {
  DraftRelayService({
    required DraftBleFollower parent,
    BlePeripheral? ble,
    int maxChildren = 3,
  }) : _parent = parent,
       _server = DraftBleLeader(
         ble: ble,
         isRelay: true,
         maxDirectLinks: maxChildren,
         forwardDecklistRequests: true,
       );

  final DraftBleFollower _parent;
  final DraftBleLeader _server;

  String? _decklistRequester;
  bool _started = false;

  int get childCount => _server.connectedDeviceCount;

  Future<void> start(DraftState state) async {
    if (_started) return;
    _server.onCommandReceived = _onChildCommand;
    await _server.startAsLeader(state);
    _started = true;
  }

  /// Re-broadcasts a snapshot applied from the parent to all children.
  Future<void> pushState(DraftState state) async {
    if (!_started) return;
    await _server.pushState(state);
  }

  /// Routes a bulk decklist payload to the child that requested it.
  void forwardDecklists(int seq, Uint8List payload) {
    final requester = _decklistRequester;
    if (requester == null) return;
    _server.sendReliableFrame(
      requester,
      seq,
      DraftFrame.encode(DraftProtocol.decklistData, seq, payload),
    );
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _server.stop();
  }

  void _onChildCommand(String deviceId, DraftCommand cmd) {
    if (cmd is DecklistRequest) {
      _decklistRequester = deviceId;
    }
    _parent
        .sendCommand(cmd)
        .catchError((Object e) => _log('[RELAY] forward failed: $e'));
  }
}

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print(msg);
}

import 'dart:async';
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
/// requests are remembered so the bulk response can be routed back to every
/// child that asked.
///
/// The relay serves its children for the entire session — including once the
/// lobby closes — because children have no way to migrate to the host while
/// their link stays up. While its uplink is down it pauses advertising so
/// nobody attaches to a relay that cannot reach the host. After the lobby it
/// keeps advertising with the real free capacity so a reconnecting peer can
/// still find a parent; the host rejects genuinely new players.
class DraftRelayService {
  DraftRelayService({
    required DraftBleFollower parent,
    BlePeripheral? ble,
    int maxChildren = 3,
    int depth = 1,
  }) : _parent = parent,
       _server = DraftBleLeader(
         ble: ble,
         isRelay: true,
         maxDirectLinks: maxChildren,
         forwardDecklistRequests: true,
         depth: depth,
       );

  final DraftBleFollower _parent;
  final DraftBleLeader _server;

  final Set<String> _decklistRequesters = {};
  StreamSubscription<bool>? _parentConnectedSub;
  StreamSubscription<String>? _childConnectedSub;
  StreamSubscription<String>? _childDisconnectedSub;
  bool _started = false;
  bool _acceptingChildren = true;
  bool _parentConnected = true;

  int get childCount => _server.connectedDeviceCount;

  /// BLE device ids of the direct children this relay currently serves.
  /// Used to keep reconnect scans from attaching to one of our own children.
  Set<String> get childDeviceIds => _server.connectedDeviceIds;

  Future<void> start(DraftState state) async {
    if (_started) return;
    _parentConnectedSub = _parent.leaderConnected.listen(
      _onParentConnectionChanged,
    );
    _server.onCommandReceived = _onChildCommand;
    await _server.startAsLeader(state);
    // Stop advertising as soon as the last child slot is taken. Without this
    // several peers can subscribe during the 300 ms capacity refresh window
    // and overload a relay beyond its configured child limit.
    _childConnectedSub = _server.followerConnected?.listen(
      (_) => _applyAdvertisingPolicy(),
    );
    _childDisconnectedSub = _server.followerDisconnected?.listen(
      (_) => _applyAdvertisingPolicy(),
    );
    _started = true;
    _applyAdvertisingPolicy();
  }

  /// Re-broadcasts a snapshot applied from the parent to all children.
  Future<void> pushState(DraftState state) async {
    if (!_started) return;
    await _server.pushState(state);
  }

  /// Controls whether this relay advertises for new children. Existing
  /// children keep their links either way.
  void setAcceptingChildren(bool value) {
    if (_acceptingChildren == value) return;
    _acceptingChildren = value;
    if (_started) _applyAdvertisingPolicy();
  }

  /// Routes a bulk decklist payload to every child that is waiting for it.
  void forwardDecklists(int seq, Uint8List payload) {
    if (_decklistRequesters.isEmpty) return;
    final frame = DraftFrame.encode(DraftProtocol.decklistData, seq, payload);
    for (final requester in _decklistRequesters) {
      _server.sendReliableFrame(requester, seq, frame);
    }
    _decklistRequesters.clear();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _parentConnectedSub?.cancel();
    _parentConnectedSub = null;
    final childConnectedSub = _childConnectedSub;
    _childConnectedSub = null;
    unawaited(childConnectedSub?.cancel());
    final childDisconnectedSub = _childDisconnectedSub;
    _childDisconnectedSub = null;
    unawaited(childDisconnectedSub?.cancel());
    _decklistRequesters.clear();
    await _server.stop();
  }

  void _onParentConnectionChanged(bool connected) {
    if (_parentConnected == connected) return;
    _parentConnected = connected;
    _log('[RELAY] parent link ${connected ? "up" : "down"}');
    if (_started) _applyAdvertisingPolicy();
  }

  void _applyAdvertisingPolicy() {
    if (!_parentConnected) {
      _server.pauseAdvertising();
      return;
    }
    // During the lobby, stop advertising once the relay is full so several
    // simultaneous joiners cannot overload it. Once the lobby closes, keep
    // advertising with the real free capacity so a reconnecting peer can
    // still find a parent; the host rejects genuinely new players.
    final full = _server.connectedDeviceCount >= _server.maxDirectLinks;
    if (_acceptingChildren && full) {
      _server.pauseAdvertising();
    } else {
      _server.resumeAdvertising();
    }
  }

  void _onChildCommand(String deviceId, DraftCommand cmd) {
    if (cmd is DecklistRequest) {
      _decklistRequesters.add(deviceId);
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

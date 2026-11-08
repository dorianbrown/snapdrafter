import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/draft_ble_follower.dart';
import 'package:snapdrafter/services/draft/draft_ble_leader.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:snapdrafter/services/draft/draft_relay.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';

import 'network.dart';

/// Builds a complete host + follower draft on top of a [FakeBleNetwork].
///
/// Unlike the original convergence helper, followers join concurrently and
/// discover their own parent, so capacity refreshes, scan timing, relay
/// formation and connection-limit races are all exercised.
class BleSimCluster {
  BleSimCluster(
    this.network, {
    this.seatCount = 8,
    this.hostCapacity = 4,
    this.relayMaxChildren = 3,
    this.useRelays = true,
    this.enforceAppLinkCaps = false,
    int? seed,
  }) : _random = Random(seed ?? network.hashCode);

  final FakeBleNetwork network;
  final int seatCount;
  final int hostCapacity;
  final int relayMaxChildren;
  final bool useRelays;

  /// When true, the fake platform enforces the app's configured link caps
  /// (hostCapacity / relayMaxChildren) instead of the platform maximum. This
  /// is for deterministic deep-relay topology tests, not load tests.
  final bool enforceAppLinkCaps;

  final Random _random;
  final List<DraftSessionNotifier> notifiers = [];
  final Map<String, FakeBleNode> nodes = {};

  DraftSessionNotifier? _host;
  DraftSessionNotifier get host => _host!;

  bool get started => _host != null && notifiers.length == seatCount;

  bool get converged {
    final hostState = _host?.state;
    if (hostState == null || notifiers.length != seatCount) return false;
    final seq = hostState.sequenceNumber;
    return notifiers.every(
      (n) =>
          !n.isReconnecting &&
          n.state != null &&
          n.state!.players.length == seatCount &&
          n.state!.sequenceNumber == seq,
    );
  }

  /// Starts the host, then joins every follower concurrently.
  ///
  /// [joinJitter] spreads scan/connect attempts over a window so several
  /// followers race for the same capacity, like real players tapping Join.
  Future<void> start({
    String name = 'Simulation',
    Duration joinJitter = const Duration(seconds: 2),
    bool concurrent = true,
  }) async {
    final hostNode = network.addNode('host');
    nodes['host'] = hostNode;
    if (enforceAppLinkCaps) {
      hostNode.maxPeripheralConnectionsOverride = hostCapacity;
    }
    final host = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () => DraftBleLeader(
        ble: hostNode.peripheral,
        maxDirectLinks: hostCapacity,
        tickInterval: network.profile.tickInterval,
        linkAckTimeout: network.profile.linkAckTimeout,
        linkChunkPacing: network.profile.linkChunkPacing,
        onLinkRetry: (deviceId, attempt) =>
            network.metrics.recordRetry('host->$deviceId'),
      ),
      reconnectDelaysSeconds: network.profile.reconnectDelaysSeconds,
    );
    _host = host;
    notifiers.add(host);
    await host.createAndHost(
      name: name,
      seatCount: seatCount,
      playerName: 'Host',
      maxDirectLinks: hostCapacity,
      relayMaxChildren: relayMaxChildren,
    );

    final joins = <Future<void>>[];
    for (var i = 1; i < seatCount; i++) {
      final id = 'p$i';
      final node = network.addNode(id);
      nodes[id] = node;
      if (enforceAppLinkCaps && useRelays) {
        node.maxPeripheralConnectionsOverride = relayMaxChildren;
      }
      final follower = DraftSessionNotifier(
        myDeviceId: id,
        bleFollowerFactory: () => DraftBleFollower(
          ble: node.central,
          myDeviceId: id,
          connectTimeout: const Duration(seconds: 15),
          initialStateTimeout: const Duration(seconds: 5),
          resyncTimeout: const Duration(seconds: 3),
        ),
        relayFactory: useRelays
            ? (parent, maxChildren, depth) => DraftRelayService(
                parent: parent,
                ble: node.peripheral,
                maxChildren: maxChildren,
                depth: depth,
              )
            : null,
        reconnectDelaysSeconds: network.profile.reconnectDelaysSeconds,
        joinRetryAttempts: 5,
      );
      notifiers.add(follower);
      joins.add(_joinWhenReady(follower, node, id, joinJitter));
    }

    if (concurrent) {
      await Future.wait(joins);
    } else {
      for (final join in joins) {
        await join;
      }
    }
  }

  Future<void> _joinWhenReady(
    DraftSessionNotifier follower,
    FakeBleNode node,
    String id,
    Duration joinJitter,
  ) async {
    if (joinJitter.inMilliseconds > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: _random.nextInt(joinJitter.inMilliseconds + 1)),
      );
    }

    for (var attempt = 0; attempt < 16; attempt++) {
      final scanner = DraftBleFollower(ble: node.central);
      DiscoveredDraft? discovered;
      try {
        discovered = await scanner.discoverBestParent(
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {
        discovered = null;
      } finally {
        await scanner.stopScan();
      }

      if (discovered != null) {
        try {
          await follower.joinDraft(
            leaderDeviceId: discovered.deviceId,
            playerName: 'Player $id',
            parentDepth: discovered.depth,
            draftId: discovered.draftId,
          );
          return;
        } catch (_) {
          // Capacity may have changed between scan and connect. Discover again.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    // Last resort: connect to the host directly. The notifier's reconnect
    // loop can still move us to a relay if the host is full.
    await follower.joinDraft(leaderDeviceId: 'host', playerName: 'Player $id');
  }

  /// Checks the invariants every converged draft must satisfy.
  void assertInvariants() {
    final states = notifiers.map((n) => n.state).toList();
    expect(
      states.every((s) => s != null),
      isTrue,
      reason: 'every node should have state',
    );

    final sequence = states.first!.sequenceNumber;
    final ids = <String>{};
    for (final state in states) {
      expect(
        state!.sequenceNumber,
        sequence,
        reason: 'all nodes should share one sequence',
      );
      expect(state.players.length, seatCount, reason: 'all players seated');
      for (final player in state.players) {
        ids.add(player.deviceId);
      }
    }
    expect(ids.length, seatCount, reason: 'player ids must be unique');

    final parentOf = <String, String?>{'host': null};
    for (final notifier in notifiers) {
      if (notifier.isFollower) {
        parentOf[notifier.myDeviceId] = notifier.parentDeviceId;
      }
    }
    for (final id in parentOf.keys) {
      final seen = <String>{};
      var current = id;
      while (current != 'host') {
        expect(
          seen.add(current),
          isTrue,
          reason: 'parent cycle involving $current',
        );
        current = parentOf[current] ?? 'host';
      }
    }

    final hostNode = nodes['host']!;
    expect(
      hostNode.incomingLinks.length,
      lessThanOrEqualTo(network.profile.maxPeripheralConnections),
      reason: 'host exceeded the platform link limit',
    );
    for (final notifier in notifiers.where((n) => n.isRelaying)) {
      expect(
        notifier.relayChildCount,
        lessThanOrEqualTo(network.profile.maxPeripheralConnections),
        reason: '${notifier.myDeviceId} exceeded the platform link limit',
      );
    }
    for (final notifier in notifiers) {
      expect(
        notifier.isReconnecting,
        isFalse,
        reason: '${notifier.myDeviceId} is still reconnecting',
      );
    }
  }

  Future<void> dispose() async {
    for (final notifier in notifiers.reversed) {
      try {
        await notifier.leaveDraft();
      } catch (_) {}
    }
    network.dispose();
  }
}

/// Advances [async] until [predicate] is true or the simulated timeout ends.
void pumpUntil(
  FakeAsync async,
  bool Function() predicate, {
  Duration step = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 90),
}) {
  var elapsed = Duration.zero;
  while (!predicate()) {
    if (elapsed >= timeout) {
      throw TimeoutException(
        'pumpUntil timed out after $timeout (elapsed $elapsed)',
      );
    }
    async.elapse(step);
    elapsed += step;
  }
}

/// Advances simulated time by [duration].
void pumpFor(FakeAsync async, Duration duration) {
  async.elapse(duration);
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/services/draft/draft_ble_follower.dart';
import 'package:snapdrafter/services/draft/draft_ble_leader.dart';
import 'package:snapdrafter/services/draft/draft_relay.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';

import '../../support/fake_ble_network.dart';

/// Waits until [predicate] is true or [timeout] elapses.
Future<void> waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
  Duration poll = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('waitUntil timed out after $timeout');
    }
    await Future<void>.delayed(poll);
  }
}

class _Cluster {
  _Cluster(this.network, this.notifiers);

  final FakeBleNetwork network;
  final List<DraftSessionNotifier> notifiers;

  DraftSessionNotifier get host => notifiers.first;

  Future<void> tearDown() async {
    for (final notifier in notifiers.reversed) {
      try {
        await notifier.leaveDraft();
      } catch (_) {}
    }
    for (final node in network.nodes.values) {
      node.central.dispose();
      node.peripheral.dispose();
    }
  }
}

Future<_Cluster> startCluster(
  FakeBleNetwork network, {
  int followers = 7,
  int seatCount = 8,
}) async {
  final hostNode = network.addNode('host');
  final host = DraftSessionNotifier(
    myDeviceId: 'host',
    bleLeaderFactory: () => DraftBleLeader(ble: hostNode.peripheral),
  );
  final notifiers = <DraftSessionNotifier>[host];
  await host.createAndHost(
    name: 'Convergence',
    seatCount: seatCount,
    playerName: 'Host',
  );

  for (var i = 1; i <= followers; i++) {
    final node = network.addNode('p$i');
    final follower = DraftSessionNotifier(
      myDeviceId: 'p$i',
      bleFollowerFactory: () =>
          DraftBleFollower(ble: node.central, myDeviceId: 'p$i'),
    );
    notifiers.add(follower);
    await follower.joinDraft(leaderDeviceId: 'host', playerName: 'Player $i');
  }
  return _Cluster(network, notifiers);
}

void main() {
  test('8 nodes converge with no packet loss', () async {
    final network = FakeBleNetwork(
      mtu: 185,
      maxConnectionsPerNode: 8,
      latency: const Duration(milliseconds: 1),
    );
    final cluster = await startCluster(network);
    addTearDown(cluster.tearDown);

    await waitUntil(
      () =>
          cluster.notifiers.length == 8 &&
          cluster.notifiers.every((n) => n.state?.players.length == 8),
      timeout: const Duration(seconds: 30),
    );

    final seqs = cluster.notifiers
        .map((n) => n.state!.sequenceNumber)
        .toSet();
    expect(seqs.length, 1, reason: 'all nodes should share one sequence');
    expect(cluster.network.droppedPackets, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('8 nodes converge after a deterministic lost chunk', () async {
    final network = FakeBleNetwork(
      mtu: 185,
      maxConnectionsPerNode: 8,
      latency: const Duration(milliseconds: 1),
    );

    // Drop exactly one packet partway through the run. The reliable session
    // must retransmit (or a tick must trigger a resync) and converge anyway.
    var packetsSeen = 0;
    network.dropPolicy = (_) {
      packetsSeen++;
      return packetsSeen == 25;
    };

    final cluster = await startCluster(network);
    addTearDown(cluster.tearDown);

    await waitUntil(
      () => cluster.notifiers.every((n) => n.state?.players.length == 8),
      timeout: const Duration(seconds: 40),
    );

    final seqs = cluster.notifiers
        .map((n) => n.state!.sequenceNumber)
        .toSet();
    expect(seqs.length, 1);
    expect(network.droppedPackets, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('8 nodes converge under 10% random packet loss', () async {
    final network = FakeBleNetwork(
      mtu: 185,
      maxConnectionsPerNode: 8,
      dropRate: 0.10,
      latency: const Duration(milliseconds: 1),
      seed: 42,
    );
    final cluster = await startCluster(network);
    addTearDown(cluster.tearDown);

    await waitUntil(
      () => cluster.notifiers.every((n) => n.state?.players.length == 8),
      timeout: const Duration(seconds: 60),
    );

    final seqs = cluster.notifiers
        .map((n) => n.state!.sequenceNumber)
        .toSet();
    expect(seqs.length, 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('decklists are fetched on demand after being stripped', () async {
    final network = FakeBleNetwork(
      mtu: 185,
      maxConnectionsPerNode: 8,
      latency: const Duration(milliseconds: 1),
    );
    final cluster = await startCluster(network);
    addTearDown(cluster.tearDown);

    await waitUntil(
      () => cluster.notifiers.every((n) => n.state?.players.length == 8),
      timeout: const Duration(seconds: 30),
    );

    final ids = List.generate(40, (i) => 'card-${i.toString().padLeft(4, '0')}');
    final accepted = await cluster.notifiers[1].submitDecklist(
      mainboardScryfallIds: ids,
      sideboardScryfallIds: const ['side-1'],
    );
    expect(accepted, isTrue);

    // Live snapshots carry only the submission flag.
    await waitUntil(
      () =>
          cluster.notifiers[2].state?.getPlayer('p1')?.decklistSubmitted ==
          true,
      timeout: const Duration(seconds: 20),
    );
    expect(
      cluster.notifiers[2].state!.getPlayer('p1')!.decklistMainboard,
      isNull,
    );

    // Contents arrive automatically once the submission is detected; the
    // snapshot itself only carried the flag.
    await waitUntil(
      () => cluster.notifiers[2].decklistFor('p1') != null,
      timeout: const Duration(seconds: 30),
    );
    final fetched = cluster.notifiers[2].decklistFor('p1')!;
    expect(fetched.mainboard.length, 40);
    expect(fetched.sideboard, const ['side-1']);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('8 nodes converge with per-node capacity of 4 via relays', () async {
    final network = FakeBleNetwork(
      mtu: 185,
      maxConnectionsPerNode: 4,
      latency: const Duration(milliseconds: 1),
    );

    final hostNode = network.addNode('host');
    final host = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () =>
          DraftBleLeader(ble: hostNode.peripheral, maxDirectLinks: 4),
    );
    final notifiers = <DraftSessionNotifier>[host];
    await host.createAndHost(
      name: 'Relay',
      seatCount: 8,
      playerName: 'Host',
    );

    for (var i = 1; i <= 7; i++) {
      final node = network.addNode('p$i');
      final follower = DraftSessionNotifier(
        myDeviceId: 'p$i',
        bleFollowerFactory: () =>
            DraftBleFollower(ble: node.central, myDeviceId: 'p$i'),
        relayFactory: (parent, maxChildren) => DraftRelayService(
          parent: parent,
          ble: node.peripheral,
          maxChildren: maxChildren,
        ),
      );
      notifiers.add(follower);

      final parent = await _findParent(node);
      await follower.joinDraft(leaderDeviceId: parent, playerName: 'Player $i');
    }

    addTearDown(() async {
      for (final notifier in notifiers.reversed) {
        try {
          await notifier.leaveDraft();
        } catch (_) {}
      }
      for (final node in network.nodes.values) {
        node.central.dispose();
        node.peripheral.dispose();
      }
    });

    await waitUntil(
      () => notifiers.every((n) => n.state?.players.length == 8),
      timeout: const Duration(seconds: 60),
    );

    final seqs = notifiers
        .map((n) => n.state!.sequenceNumber)
        .toSet();
    expect(seqs.length, 1);

    // The host must not have exceeded its connection limit, and at least one
    // relay must have taken children.
    expect(hostNode.incomingLinks.length, lessThanOrEqualTo(4));
    final relayedChildren = network.nodes.values
        .where((n) => n.deviceId != 'host')
        .where((n) => n.incomingLinks.isNotEmpty)
        .toList();
    expect(relayedChildren, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('3 nodes with host capacity 1 route the third through a relay', () async {
    final network = FakeBleNetwork(
      mtu: 185,
      maxConnectionsPerNode: 4,
      latency: const Duration(milliseconds: 1),
    );

    final hostNode = network.addNode('host');
    final host = DraftSessionNotifier(
      myDeviceId: 'host',
      bleLeaderFactory: () =>
          DraftBleLeader(ble: hostNode.peripheral, maxDirectLinks: 1),
    );
    final notifiers = <DraftSessionNotifier>[host];
    await host.createAndHost(name: 'Smoke', seatCount: 3, playerName: 'Host');

    // First follower connects directly to the host and becomes a relay.
    final relayNode = network.addNode('p1');
    final relay = DraftSessionNotifier(
      myDeviceId: 'p1',
      bleFollowerFactory: () =>
          DraftBleFollower(ble: relayNode.central, myDeviceId: 'p1'),
      relayFactory: (parent, maxChildren) => DraftRelayService(
        parent: parent,
        ble: relayNode.peripheral,
        maxChildren: maxChildren,
      ),
    );
    notifiers.add(relay);
    await relay.joinDraft(leaderDeviceId: 'host', playerName: 'Player 1');
    expect(relay.isRelaying, isTrue);

    // Give the host's debounced advertisement refresh time to publish
    // capacity 0 before the third device scans.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Third device must route through the relay because the host is full.
    final leafNode = network.addNode('p2');
    final leaf = DraftSessionNotifier(
      myDeviceId: 'p2',
      bleFollowerFactory: () =>
          DraftBleFollower(ble: leafNode.central, myDeviceId: 'p2'),
    );
    notifiers.add(leaf);
    final parent = await _findParent(leafNode);
    expect(parent, 'p1');
    await leaf.joinDraft(leaderDeviceId: parent, playerName: 'Player 2');

    addTearDown(() async {
      for (final notifier in notifiers.reversed) {
        try {
          await notifier.leaveDraft();
        } catch (_) {}
      }
      for (final node in network.nodes.values) {
        node.central.dispose();
        node.peripheral.dispose();
      }
    });

    await waitUntil(
      () => notifiers.every((n) => n.state?.players.length == 3),
      timeout: const Duration(seconds: 30),
    );

    expect(leaf.parentDeviceId, 'p1');
    expect(hostNode.incomingLinks.length, 1);
    expect(relayNode.incomingLinks.length, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Scans until a parent with free capacity appears and returns its device id.
Future<String> _findParent(FakeBleNode node) async {
  final scanner = DraftBleFollower(ble: node.central);
  final completer = Completer<String>();
  final sub = scanner.scanForDrafts().listen((draft) {
    if (!completer.isCompleted && draft.capacity > 0) {
      completer.complete(draft.deviceId);
    }
  });
  try {
    return await completer.future.timeout(const Duration(seconds: 10));
  } finally {
    await sub.cancel();
    await scanner.stopScan();
  }
}

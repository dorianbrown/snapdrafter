import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapdrafter/services/draft/draft_ble_follower.dart';
import 'package:snapdrafter/services/draft/draft_ble_leader.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:snapdrafter/services/draft/draft_relay.dart';
import 'package:snapdrafter/services/draft/draft_session_notifier.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';

import '../../support/ble_sim/network.dart';
import '../../support/ble_sim/profile.dart';
import '../../support/ble_sim/scenario.dart';

void main() {
  test(
    '8 nodes converge on a realistic Android radio with concurrent joins',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 11,
        );
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 11,
        );

        expectConverges(async, cluster);
        expect(network.metrics.notificationsDelivered, greaterThan(0));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '7 concurrent joiners fill a 4-link host and overflow through relays',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-4-link',
          maxPeripheralConnections: 4,
          maxCentralConnections: 7,
        );
        final network = FakeBleNetwork(profile: profile, seed: 22);
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 4,
          useRelays: true,
          relayMaxChildren: 3,
          seed: 22,
        );

        expectConverges(async, cluster);

        final hostNode = network.nodes['host']!;
        expect(hostNode.incomingLinks.length, lessThanOrEqualTo(4));
        final relayed = cluster.notifiers
            .where((n) => n.isFollower && n.parentDeviceId != 'host')
            .toList();
        expect(relayed.length, greaterThanOrEqualTo(3));
        final relaysWithChildren = cluster.notifiers.where(
          (n) => n.isRelaying && n.relayChildCount > 0,
        );
        expect(relaysWithChildren, isNotEmpty);

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a dropped notification is recovered by retransmit or resync',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 33,
        );
        network.dropPolicy = (index) => index == 40;
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 33,
        );

        expectConverges(async, cluster);
        expect(network.droppedPackets, 1);

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the host retries advertising after a platform error',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 44,
        );
        network.faults.failNextAdvertising('host');
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 44,
        );

        pumpUntil(
          async,
          () => cluster.host.advertisingError == null,
          timeout: const Duration(seconds: 10),
        );
        expect(network.metrics.advertisingFailures, 1);
        expectConverges(async, cluster);

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a player attached through a relay reconnects after its link drops',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-4-link',
          maxPeripheralConnections: 4,
          maxCentralConnections: 7,
        );
        final network = FakeBleNetwork(profile: profile, seed: 55);
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 4,
          useRelays: true,
          relayMaxChildren: 3,
          seed: 55,
        );
        expectConverges(async, cluster);

        final relayed = cluster.notifiers.firstWhere(
          (n) => n.isFollower && n.parentDeviceId != 'host',
        );
        final parent = relayed.parentDeviceId!;
        final node = cluster.nodes[relayed.myDeviceId]!;
        unawaited(node.central.disconnect(parent));
        pumpFor(async, const Duration(milliseconds: 200));

        expectConverges(async, cluster);
        expect(network.metrics.disconnects, greaterThanOrEqualTo(1));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a depth-2 relay keeps its children when its uplink drops',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-depth-2',
          maxPeripheralConnections: 4,
          maxCentralConnections: 4,
        );
        final network = FakeBleNetwork(profile: profile, seed: 131);
        final notifiers = <DraftSessionNotifier>[];
        final nodes = <String, FakeBleNode>{};
        late DraftSessionNotifier host;

        Future<DraftSessionNotifier> joinNode(
          String id,
          String parentId,
          int parentDepth,
        ) async {
          final node = network.addNode(id);
          nodes[id] = node;
          final notifier = DraftSessionNotifier(
            myDeviceId: id,
            bleFollowerFactory: () =>
                DraftBleFollower(ble: node.central, myDeviceId: id),
            relayFactory: (parent, maxChildren, depth) => DraftRelayService(
              parent: parent,
              ble: node.peripheral,
              maxChildren: maxChildren,
              depth: depth,
            ),
            reconnectDelaysSeconds: profile.reconnectDelaysSeconds,
            joinRetryAttempts: 5,
          );
          notifiers.add(notifier);
          await notifier.joinDraft(
            leaderDeviceId: parentId,
            playerName: id,
            parentDepth: parentDepth,
            relayMaxChildren: 2,
          );
          return notifier;
        }

        Future<void> build() async {
          final hostNode = network.addNode('host');
          nodes['host'] = hostNode;
          host = DraftSessionNotifier(
            myDeviceId: 'host',
            bleLeaderFactory: () => DraftBleLeader(
              ble: hostNode.peripheral,
              maxDirectLinks: 2,
              tickInterval: profile.tickInterval,
              linkAckTimeout: profile.linkAckTimeout,
              linkChunkPacing: profile.linkChunkPacing,
            ),
            reconnectDelaysSeconds: profile.reconnectDelaysSeconds,
            joinRetryAttempts: 5,
          );
          notifiers.add(host);
          await host.createAndHost(
            name: 'Depth',
            seatCount: 5,
            playerName: 'Host',
            maxDirectLinks: 2,
            relayMaxChildren: 2,
          );
          // host -> p1/p2 -> p3 -> p4. p3 is a depth-2 relay with a child.
          await joinNode('p1', 'host', 0);
          await joinNode('p2', 'host', 0);
          await joinNode('p3', 'p1', 1);
          await joinNode('p4', 'p3', 2);
        }

        var built = false;
        Object? buildError;
        unawaited(
          build().then<void>((_) => built = true).catchError((
            Object error,
            StackTrace stack,
          ) {
            buildError = error;
            built = true;
          }),
        );
        pumpUntil(async, () => built, timeout: const Duration(seconds: 30));
        expect(
          buildError,
          isNull,
          reason: 'controlled topology failed: $buildError',
        );
        pumpUntil(
          async,
          () => notifiers.every(
            (n) =>
                n.state?.players.length == 5 &&
                n.state!.sequenceNumber == host.state!.sequenceNumber,
          ),
        );

        final relay = notifiers.firstWhere((n) => n.myDeviceId == 'p3');
        final child = notifiers.firstWhere((n) => n.myDeviceId == 'p4');
        expect(relay.myDepth, 2);
        expect(relay.isRelaying, isTrue);
        expect(relay.relayChildCount, 1);
        expect(child.parentDeviceId, 'p3');

        unawaited(nodes['p3']!.central.disconnect('p1'));
        pumpFor(async, const Duration(milliseconds: 200));

        pumpUntil(
          async,
          () => notifiers.every(
            (n) =>
                !n.isReconnecting &&
                n.state?.sequenceNumber == host.state!.sequenceNumber,
          ),
          timeout: const Duration(seconds: 60),
        );
        expect(child.parentDeviceId, 'p3');
        expect(relay.isRelaying, isTrue);
        expect(relay.relayChildCount, 1);

        for (final notifier in notifiers.reversed) {
          unawaited(notifier.leaveDraft());
        }
        pumpFor(async, const Duration(seconds: 2));
        network.dispose();
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a long radio-off recovers on the next state change',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 141,
        );
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 141,
        );
        expectConverges(async, cluster);

        final p1 = cluster.notifiers[1];
        final p2 = cluster.notifiers[2];
        final p3 = cluster.notifiers[3];

        // Longer than the ~6 s ACK retry window, so the host declares the link
        // dead and stops sending ticks.
        network.setRadioEnabled('p1', false);
        pumpFor(async, const Duration(seconds: 12));

        unawaited(
          p2.submitDecklist(
            mainboardScryfallIds: _deckFor('p2'),
            sideboardScryfallIds: _sideboardFor('p2'),
          ),
        );
        pumpUntil(
          async,
          () =>
              cluster.host.state?.getPlayer('p2')?.decklistMainboard?.length ==
              100,
        );
        expect(
          p1.state!.sequenceNumber,
          lessThan(cluster.host.state!.sequenceNumber),
          reason: 'the paused node should have missed the decklist state',
        );

        network.setRadioEnabled('p1', true);
        pumpFor(async, const Duration(milliseconds: 500));

        unawaited(
          p3.submitDecklist(
            mainboardScryfallIds: _deckFor('p3'),
            sideboardScryfallIds: _sideboardFor('p3'),
          ),
        );
        pumpUntil(
          async,
          () =>
              cluster.host.state?.getPlayer('p3')?.decklistMainboard?.length ==
              100,
        );
        expectConverges(async, cluster, timeout: const Duration(seconds: 60));
        expect(network.droppedPackets, greaterThan(0));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a join storm survives connect, MTU, subscribe and scan failures',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-lossy-join',
          scanMissRate: 0.35,
        );
        final network = FakeBleNetwork(profile: profile, seed: 151);
        expect(network.profile.scanMissRate, 0.35);
        network.faults.failNextConnect('p2');
        network.faults.failNextSubscribe('p3');
        network.faults.failNextMtu('p4');

        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 151,
        );

        expectConverges(async, cluster, timeout: const Duration(seconds: 120));
        expect(network.faults.injectedFailures, greaterThanOrEqualTo(3));
        expect(network.metrics.connectFailures, greaterThanOrEqualTo(1));
        expect(network.metrics.scanMisses, greaterThan(0));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'eight 100-card decklists submit and fetch through relays under loss',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-relay-loss',
          maxPeripheralConnections: 4,
          maxCentralConnections: 7,
        );
        final network = FakeBleNetwork(
          profile: profile,
          seed: 161,
          dropRate: 0.05,
        );
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 4,
          useRelays: true,
          relayMaxChildren: 3,
          seed: 161,
        );
        expectConverges(async, cluster, timeout: const Duration(seconds: 120));

        final submissions = <Future<void>>[];
        for (final notifier in cluster.notifiers) {
          submissions.add(
            _submitDecklistWithRetry(
              notifier,
              _deckFor(notifier.myDeviceId),
              _sideboardFor(notifier.myDeviceId),
            ),
          );
        }
        var submitted = false;
        Object? submissionError;
        unawaited(
          Future.wait(submissions)
              .then<void>((_) {
                submitted = true;
              })
              .catchError((Object error, StackTrace stack) {
                submissionError = error;
                submitted = true;
              }),
        );
        pumpUntil(
          async,
          () => submitted,
          timeout: const Duration(seconds: 120),
        );
        expect(
          submissionError,
          isNull,
          reason: 'a player never managed to submit: $submissionError',
        );
        pumpUntil(
          async,
          () => cluster.host.state!.players.every(
            (p) => p.decklistMainboard?.length == 100,
          ),
          timeout: const Duration(seconds: 30),
        );

        final followers = cluster.notifiers.where((n) => n.isFollower);
        pumpUntil(
          async,
          () => followers.every(
            (n) => cluster.host.state!.players.every(
              (p) => n.decklistFor(p.deviceId)?.mainboard.length == 100,
            ),
          ),
          timeout: const Duration(seconds: 240),
        );

        for (final follower in followers) {
          for (final player in cluster.host.state!.players) {
            final deck = follower.decklistFor(player.deviceId)!;
            expect(deck.mainboard.length, 100);
            expect(deck.sideboard.length, 15);
          }
        }
        expect(network.droppedPackets, greaterThan(0));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'simultaneous reports and a round advance survive a reconnect',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-relay-results',
          maxPeripheralConnections: 4,
          maxCentralConnections: 7,
        );
        final network = FakeBleNetwork(profile: profile, seed: 171);
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 4,
          useRelays: true,
          relayMaxChildren: 3,
          seed: 171,
        );
        expectConverges(async, cluster);

        unawaited(cluster.host.closeLobby());
        pumpUntil(
          async,
          () => cluster.notifiers.every(
            (n) => n.state?.session.phase == DraftPhase.inProgress,
          ),
        );

        final match = cluster.host.state!.rounds[0].matches.first;
        final reporterA = cluster.notifiers.firstWhere(
          (n) => n.myDeviceId == match.playerAId,
        );
        final reporterB = cluster.notifiers.firstWhere(
          (n) => n.myDeviceId == match.playerBId,
        );
        final churn = cluster.notifiers.firstWhere(
          (n) =>
              n.isFollower &&
              n.parentDeviceId != 'host' &&
              n.myDeviceId != match.playerAId &&
              n.myDeviceId != match.playerBId,
        );

        final churnNode = cluster.nodes[churn.myDeviceId]!;
        unawaited(churnNode.central.disconnect(churn.parentDeviceId!));

        // Both players report the same match at once, each claiming the win.
        unawaited(
          reporterA.submitResult(
            roundNumber: 1,
            matchId: match.matchId,
            myWins: 2,
            opponentWins: 0,
          ),
        );
        unawaited(
          reporterB.submitResult(
            roundNumber: 1,
            matchId: match.matchId,
            myWins: 2,
            opponentWins: 0,
          ),
        );

        pumpUntil(
          async,
          () =>
              cluster.host.state!.rounds[0].matches
                  .firstWhere((m) => m.matchId == match.matchId)
                  .status ==
              MatchStatus.confirmed,
          timeout: const Duration(seconds: 30),
        );

        unawaited(cluster.host.advanceRound());
        pumpUntil(
          async,
          () => cluster.host.state!.rounds.length == 2,
          timeout: const Duration(seconds: 30),
        );
        try {
          pumpUntil(
            async,
            () => cluster.notifiers.every((n) => n.state?.rounds.length == 2),
            timeout: const Duration(seconds: 60),
          );
        } on TimeoutException {
          for (final n in cluster.notifiers) {
            // ignore: avoid_print
            print(
              '${n.myDeviceId}: rounds=${n.state?.rounds.length} '
              'phase=${n.state?.session.phase.name} '
              'reconnecting=${n.isReconnecting} '
              'parent=${n.parentDeviceId} '
              'seq=${n.state?.sequenceNumber}',
            );
          }
          rethrow;
        }
        expectConverges(async, cluster);

        final finalMatch = cluster.host.state!.rounds[0].matches.firstWhere(
          (m) => m.matchId == match.matchId,
        );
        expect(finalMatch.status, MatchStatus.confirmed);
        expect(
          (finalMatch.aWins == 2 && finalMatch.bWins == 0) ||
              (finalMatch.aWins == 0 && finalMatch.bWins == 2),
          isTrue,
        );
        final wins = cluster.host.state!.players.fold<int>(
          0,
          (sum, p) => sum + p.matchWins,
        );
        final losses = cluster.host.state!.players.fold<int>(
          0,
          (sum, p) => sum + p.matchLosses,
        );
        final draws = cluster.host.state!.players.fold<int>(
          0,
          (sum, p) => sum + p.matchDraws,
        );
        expect(wins + losses + draws, 2);

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a node that misses traffic resyncs when its radio returns',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 66,
        );
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 66,
        );
        expectConverges(async, cluster);

        network.setRadioEnabled('p1', false);
        pumpFor(async, const Duration(seconds: 2));
        network.setRadioEnabled('p1', true);

        expectConverges(async, cluster);
        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a 23-byte MTU still carries a decklist in both directions',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-mtu-23',
          mtu: 23,
          maxPeripheralConnections: 1,
          maxCentralConnections: 1,
        );
        final network = FakeBleNetwork(profile: profile, seed: 77);
        final cluster = startCluster(
          async,
          network,
          seatCount: 2,
          hostCapacity: 1,
          useRelays: false,
          seed: 77,
        );
        expectConverges(async, cluster);

        final ids = List.generate(
          40,
          (i) => 'card-${i.toString().padLeft(4, '0')}',
        );
        bool? accepted;
        unawaited(
          cluster.notifiers[1]
              .submitDecklist(
                mainboardScryfallIds: ids,
                sideboardScryfallIds: const ['side-1'],
              )
              .then<void>((value) => accepted = value)
              .catchError((Object error) => accepted = false),
        );
        pumpUntil(async, () => accepted != null);
        expect(accepted, isTrue);

        pumpUntil(
          async,
          () =>
              cluster.host.state?.getPlayer('p1')?.decklistMainboard?.length ==
              40,
        );
        pumpUntil(async, () => cluster.notifiers[1].decklistFor('p1') != null);
        final fetched = cluster.notifiers[1].decklistFor('p1')!;
        expect(fetched.mainboard.length, 40);
        expect(fetched.sideboard, const ['side-1']);

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '100 seeded 8-node runs converge',
    () {
      const seeds = 100;
      for (var seed = 0; seed < seeds; seed++) {
        Object? failure;
        StackTrace? failureStack;
        final log = StringBuffer();
        runZoned(
          () {
            try {
              fakeAsync((async) {
                final network = FakeBleNetwork(
                  profile: BleSimProfile.android,
                  seed: seed,
                  dropRate: 0.02,
                );
                final cluster = startCluster(
                  async,
                  network,
                  hostCapacity: 7,
                  useRelays: false,
                  seed: seed,
                  joinJitter: const Duration(seconds: 1),
                );
                try {
                  pumpUntil(
                    async,
                    () => cluster.converged,
                    timeout: const Duration(seconds: 60),
                  );
                  cluster.assertInvariants();
                } on TimeoutException {
                  log.writeln('seed $seed: ${network.metrics.summary()}');
                  for (final notifier in cluster.notifiers) {
                    log.writeln(
                      '  ${notifier.myDeviceId}: ${notifier.role.name} '
                      'reconnecting=${notifier.isReconnecting} '
                      'seq=${notifier.state?.sequenceNumber} '
                      'players=${notifier.state?.players.length} '
                      'parent=${notifier.parentDeviceId}',
                    );
                  }
                  rethrow;
                } finally {
                  disposeCluster(async, cluster);
                }
              });
            } catch (error, stack) {
              failure = error;
              failureStack = stack;
            }
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => log.writeln(line),
          ),
        );
        if (failure != null) {
          // ignore: avoid_print
          print(log.toString());
          fail('seed $seed failed: $failure\n$failureStack');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'a relayed player can report a match result on a realistic radio',
    () {
      fakeAsync((async) {
        final profile = BleSimProfile.android.copyWith(
          name: 'android-4-link',
          maxPeripheralConnections: 4,
          maxCentralConnections: 7,
        );
        final network = FakeBleNetwork(profile: profile, seed: 111);
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 4,
          useRelays: true,
          relayMaxChildren: 3,
          seed: 111,
        );
        expectConverges(async, cluster);

        unawaited(cluster.host.closeLobby());
        pumpUntil(
          async,
          () => cluster.notifiers.every(
            (n) => n.state?.session.phase == DraftPhase.inProgress,
          ),
        );

        final reporter = cluster.notifiers.firstWhere(
          (n) => n.isFollower && n.parentDeviceId != 'host',
        );
        final match = reporter.state!.getMyMatch(reporter.myDeviceId, 1)!;
        unawaited(
          reporter.submitResult(
            roundNumber: 1,
            matchId: match.matchId,
            myWins: 2,
            opponentWins: 0,
          ),
        );

        pumpUntil(
          async,
          () =>
              cluster.host.state!.rounds[0].matches
                  .firstWhere((m) => m.matchId == match.matchId)
                  .status ==
              MatchStatus.reported,
        );
        expectConverges(async, cluster);

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '8 nodes converge with the iOS peripheral profile',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(profile: BleSimProfile.ios, seed: 121);
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 121,
        );

        expectConverges(async, cluster);
        // iOS only reveals a link on subscription, so this also proves the host
        // does not depend on connect events for capacity and fan-out.
        expect(network.nodes['host']!.incomingLinks.length, greaterThan(0));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a host accepting more than its advertised capacity still converges',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 99,
        );
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 3,
          useRelays: false,
          seed: 99,
        );

        expectConverges(async, cluster);
        // maxDirectLinks is a soft topology hint: the platform still allows the
        // extra links, and the draft must stay usable.
        expect(network.nodes['host']!.incomingLinks.length, greaterThan(3));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'duplicate, reordered, and corrupted packets do not wedge a draft',
    () {
      fakeAsync((async) {
        final network = FakeBleNetwork(
          profile: BleSimProfile.android,
          seed: 88,
        );
        network.faults.duplicateEvery = 25;
        network.faults.reorderEvery = 40;
        network.faults.corruptEvery = 60;
        final cluster = startCluster(
          async,
          network,
          hostCapacity: 7,
          useRelays: false,
          seed: 88,
        );

        expectConverges(async, cluster, timeout: const Duration(seconds: 120));
        expect(network.faults.duplicatedPackets, greaterThan(0));
        expect(network.faults.reorderedPackets, greaterThan(0));
        expect(network.faults.corruptedPackets, greaterThan(0));

        disposeCluster(async, cluster);
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('scan timeout returns null under simulated time', () {
    fakeAsync((async) {
      final network = FakeBleNetwork(profile: BleSimProfile.android);
      final node = network.addNode('p1');
      final follower = DraftBleFollower(ble: node.central);
      var done = false;
      DiscoveredDraft? discovered;
      unawaited(
        follower
            .discoverBestParent(timeout: const Duration(milliseconds: 200))
            .then((value) {
              discovered = value;
              done = true;
            }),
      );
      pumpUntil(async, () => done, timeout: const Duration(seconds: 2));
      expect(discovered, isNull);
      unawaited(follower.stopScan());
      pumpFor(async, const Duration(milliseconds: 100));
      network.dispose();
    });
  });
}

BleSimCluster startCluster(
  FakeAsync async,
  FakeBleNetwork network, {
  int seatCount = 8,
  int hostCapacity = 7,
  bool useRelays = false,
  int relayMaxChildren = 3,
  bool enforceAppLinkCaps = false,
  int? seed,
  Duration joinJitter = const Duration(seconds: 2),
}) {
  final cluster = BleSimCluster(
    network,
    seatCount: seatCount,
    hostCapacity: hostCapacity,
    relayMaxChildren: relayMaxChildren,
    useRelays: useRelays,
    enforceAppLinkCaps: enforceAppLinkCaps,
    seed: seed,
  );

  var started = false;
  Object? startError;
  unawaited(
    cluster
        .start(joinJitter: joinJitter)
        .then<void>((_) {
          started = true;
        })
        .catchError((Object error, StackTrace stack) {
          startError = error;
          started = true;
        }),
  );

  pumpUntil(async, () => started, timeout: const Duration(seconds: 30));
  expect(startError, isNull, reason: 'cluster failed to start: $startError');
  return cluster;
}

void expectConverges(
  FakeAsync async,
  BleSimCluster cluster, {
  Duration timeout = const Duration(seconds: 90),
}) {
  try {
    pumpUntil(async, () => cluster.converged, timeout: timeout);
  } on TimeoutException {
    // ignore: avoid_print
    print('simulation failed: ${cluster.network.metrics.summary()}');
    for (final notifier in cluster.notifiers) {
      // ignore: avoid_print
      print(
        '${notifier.myDeviceId}: role=${notifier.role.name} '
        'reconnecting=${notifier.isReconnecting} '
        'seq=${notifier.state?.sequenceNumber} '
        'players=${notifier.state?.players.length} '
        'parent=${notifier.parentDeviceId}',
      );
    }
    rethrow;
  }
  cluster.assertInvariants();
}

void disposeCluster(FakeAsync async, BleSimCluster cluster) {
  unawaited(cluster.dispose());
  pumpFor(async, const Duration(seconds: 2));
}

List<String> _deckFor(String playerId) =>
    List.generate(100, (i) => '$playerId-mb-${i.toString().padLeft(3, '0')}');

List<String> _sideboardFor(String playerId) =>
    List.generate(15, (i) => '$playerId-sb-${i.toString().padLeft(2, '0')}');

Future<void> _submitDecklistWithRetry(
  DraftSessionNotifier notifier,
  List<String> mainboard,
  List<String> sideboard, {
  int attempts = 8,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (await notifier.submitDecklist(
      mainboardScryfallIds: mainboard,
      sideboardScryfallIds: sideboard,
    )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('${notifier.myDeviceId} could not submit a decklist');
}

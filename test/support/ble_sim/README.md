# BLE draft simulator

An in-memory BLE network that runs complete drafts — host, relays, followers,
decklists and reconnects — without radios or phones.

It is deliberately **not** a Bluetooth stack emulator. It models the parts of
the platform that tend to break an eight-device draft:

- one radio per node shared by its central and peripheral roles,
- a connection interval and one packet per slot, so more links means less
  throughput per link,
- realistic connect / MTU / service-discovery / subscribe delays,
- periodic advertising and scanning, advertising restart gaps and payload
  limits,
- separate central and peripheral connection limits,
- bounded radio queues with silent notification loss,
- packet loss, duplication, reordering and corruption,
- timed disconnects, radio-off pauses and advertising failures.

Everything runs on [`fake_async`](https://pub.dev/packages/fake_async), so a
90-second draft takes milliseconds of real time. A run is deterministic for a
given seed.

## Profiles

`BleSimProfile` in `profile.dart` selects the platform model:

| Profile | MTU | Link slots | Connection interval | Notes |
| --- | ---: | ---: | ---: | --- |
| `BleSimProfile.ideal` | 185 | 8 | 1 ms | Original instant fake; existing tests use this |
| `BleSimProfile.android` | 517 | 7 | 15 ms | Android connection events |
| `BleSimProfile.ios` | 185 | 7 | 30 ms | Link only visible after subscribe |
| `BleSimProfile.androidLowEnd` | 517 | 4 | 30 ms | Forces relay topology |

Use `copyWith(...)` to tighten a profile for a scenario, for example:

```dart
final profile = BleSimProfile.android.copyWith(
  maxPeripheralConnections: 4,
  mtu: 23,
);
```

## Writing a scenario

```dart
test('eight players converge', () {
  fakeAsync((async) {
    final network = FakeBleNetwork(
      profile: BleSimProfile.android,
      seed: 11,
      dropRate: 0.02,
    );
    final cluster = BleSimCluster(
      network,
      seatCount: 8,
      hostCapacity: 4,
      useRelays: true,
      seed: 11,
    );

    var started = false;
    unawaited(cluster.start(joinJitter: const Duration(seconds: 2))
        .then((_) => started = true));

    pumpUntil(async, () => started);
    pumpUntil(async, () => cluster.converged);
    cluster.assertInvariants();
  });
});
```

Followers join concurrently and discover their own parent, so capacity
refreshes, relay formation and connection-limit races are exercised.

For deterministic deep-relay topologies where the app's configured limit is
lower than the platform limit, pass `enforceAppLinkCaps: true`. The fake
platform then refuses links beyond `hostCapacity` / `relayMaxChildren`, which
is useful for testing relay-child retention without joining races:

```dart
final cluster = BleSimCluster(
  network,
  seatCount: 8,
  hostCapacity: 2,
  relayMaxChildren: 1,
  enforceAppLinkCaps: true,
);
```

`BleSimCluster.assertInvariants()` checks:

- every node has state,
- every node shares the same sequence number,
- every player is present exactly once,
- the parent graph has no cycles,
- no node exceeds its platform link limit,
- no node is still reconnecting.

## Faults and metrics

`network.faults` provides deterministic injections:

```dart
network.faults.failNextAdvertising('host');
network.faults.failNextConnect('p3');
network.faults.failNextSubscribe('p4');
network.faults.failNextWrite('p1');
network.faults.forcedMtu = 23;
network.faults.duplicateEvery = 25;
network.faults.reorderEvery = 40;
network.faults.corruptEvery = 60;
```

Schedule time-based chaos with `network.scheduleFault`:

```dart
network.scheduleFault(const Duration(seconds: 5),
    () => network.setRadioEnabled('p3', false));
network.scheduleFault(const Duration(seconds: 8),
    () => network.setRadioEnabled('p3', true));
```

`network.metrics` records connects, failures, disconnects, notifications and
writes delivered/dropped, retransmits per device, advertising failures and the
maximum radio queue depth.

## Running

```sh
flutter test test/services/draft/draft_simulation_test.dart
flutter test test/services/draft/draft_simulation_test.dart --plain-name "100 seeded"
```

When a seeded run fails, the test prints the seed, the metrics and each node's
role, sequence, player count and parent so the failure can be replayed.

## Limits

This bench cannot reproduce RF interference, vendor GATT failures (for example
Android status 133), real OS background suspension, or the exact radio timing
of a particular phone. Keep a small physical smoke run before release; use this
suite for everything that is logic, topology or timing.

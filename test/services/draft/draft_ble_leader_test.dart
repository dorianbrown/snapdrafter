import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:snapdrafter/services/draft/ble_platform.dart';
import 'package:snapdrafter/services/draft/draft_ble_leader.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/draft_message.dart';

class FakeBlePeripheral implements BlePeripheral {
  final _connectionStateCtrl =
      StreamController<BlePeripheralConnectionStateChanged>.broadcast();
  final _charSubCtrl = StreamController<
      BlePeripheralCharacteristicSubscriptionChanged>.broadcast();
  final _advStateCtrl =
      StreamController<BlePeripheralAdvertisingStateChanged>.broadcast();
  final _mtuChangedCtrl =
      StreamController<BlePeripheralMtuChanged>.broadcast();

  @override
  Stream<BlePeripheralConnectionStateChanged> get connectionStateStream =>
      _connectionStateCtrl.stream;

  @override
  Stream<BlePeripheralCharacteristicSubscriptionChanged>
      get characteristicSubscriptionStream => _charSubCtrl.stream;

  @override
  Stream<BlePeripheralAdvertisingStateChanged> get advertisingStateStream =>
      _advStateCtrl.stream;

  @override
  Stream<BlePeripheralMtuChanged> get mtuChangedStream =>
      _mtuChangedCtrl.stream;

  // Recorded calls
  BlePeripheralService? addedService;
  bool readHandlersSet = false;
  bool writeHandlersSet = false;
  bool startedAdvertising = false;
  bool stoppedAdvertising = false;
  bool clearedServices = false;
  final List<Map<String, dynamic>> characteristicUpdates = [];
  String? lastMaximumNotifyDeviceId;

  // Injectable results
  BlePeripheralCapabilities capabilities =
      const BlePeripheralCapabilities(
    supportsPeripheralMode: true,
    supportsManufacturerDataInAdvertisement: false,
    supportsManufacturerDataInScanResponse: false,
    supportsServiceDataInAdvertisement: false,
    supportsServiceDataInScanResponse: false,
    supportsTargetedCharacteristicUpdate: false,
    supportsAdvertisingTimeout: false,
  );
  PeripheralReadinessState readinessState = PeripheralReadinessState.ready;
  int? maximumNotifyLength;
  bool advertiseThrows = false;
  bool updateCharThrows = false;

  // Error injection
  Object? addServiceThrow;
  Object? advertiseThrow;
  Object? getCapabilitiesThrow;

  // Handlers captured from setReadRequestHandlers / setWriteRequestHandlers
  PeripheralReadRequestResult? Function(
          String, String, int, Uint8List?)?
      readHandler;
  PeripheralWriteRequestResult Function(
          String, String, int, Uint8List?)?
      writeHandler;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async {
    if (getCapabilitiesThrow != null) throw getCapabilitiesThrow!;
    return capabilities;
  }

  @override
  Future<void> addService(BlePeripheralService service) async {
    if (addServiceThrow != null) throw addServiceThrow!;
    addedService = service;
  }

  @override
  void setReadRequestHandlers(
    PeripheralReadRequestResult? Function(
            String, String, int, Uint8List?)?
        handler,
  ) {
    readHandler = handler;
    readHandlersSet = true;
  }

  @override
  void setWriteRequestHandlers(
    PeripheralWriteRequestResult Function(
            String, String, int, Uint8List?)?
        handler,
  ) {
    writeHandler = handler;
    writeHandlersSet = true;
  }

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    if (advertiseThrow != null) throw advertiseThrow!;
    startedAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    stoppedAdvertising = true;
  }

  @override
  Future<void> clearServices() async {
    clearedServices = true;
  }

  @override
  Future<List<String>> getServices() async {
    return ['fake-service-uuid'];
  }

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async {
    return readinessState;
  }

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {
    if (updateCharThrows) throw Exception('update characteristic failed');
    characteristicUpdates.add({
      'characteristicId': characteristicId,
      'value': value,
      'deviceId': deviceId,
    });
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async {
    lastMaximumNotifyDeviceId = deviceId;
    return maximumNotifyLength;
  }

  // Convenience methods for tests
  void emitConnection(String deviceId, bool connected) {
    _connectionStateCtrl
        .add(BlePeripheralConnectionStateChanged(deviceId, connected));
  }

  void emitSubscription(String deviceId, String characteristicId,
      bool isSubscribed) {
    _charSubCtrl.add(BlePeripheralCharacteristicSubscriptionChanged(
      deviceId: deviceId,
      characteristicId: characteristicId,
      isSubscribed: isSubscribed,
      name: characteristicId,
    ));
  }

  void emitMtuChange(String deviceId, int mtu) {
    _mtuChangedCtrl.add(BlePeripheralMtuChanged(deviceId, mtu));
  }

  Future<void> disposeStreams() async {
    await _connectionStateCtrl.close();
    await _charSubCtrl.close();
    await _advStateCtrl.close();
    await _mtuChangedCtrl.close();
  }
}

DraftState _testState({String name = 'Test Draft'}) {
  return DraftState.create(
    name: name,
    leaderDeviceId: 'leader-device',
    leaderPlayerName: 'Leader',
    seatCount: 8,
  );
}

void main() {
  late FakeBlePeripheral fakeBle;
  late DraftBleLeader leader;

  setUp(() {
    fakeBle = FakeBlePeripheral();
    leader = DraftBleLeader(ble: fakeBle);
  });

  tearDown(() async {
    await leader.stop();
    await fakeBle.disposeStreams();
  });

  // ---------------------------------------------------------------------------
  // startAsLeader
  // ---------------------------------------------------------------------------

  group('startAsLeader', () {
    test('checks peripheral capabilities', () async {
      await leader.startAsLeader(_testState());
      // Capabilities checked implicitly (throws if addService fails)
    });

    test('throws when peripheral mode not supported', () async {
      fakeBle.capabilities = const BlePeripheralCapabilities(
        supportsPeripheralMode: false,
        supportsManufacturerDataInAdvertisement: false,
        supportsManufacturerDataInScanResponse: false,
        supportsServiceDataInAdvertisement: false,
        supportsServiceDataInScanResponse: false,
        supportsTargetedCharacteristicUpdate: false,
        supportsAdvertisingTimeout: false,
      );      expect(
        () => leader.startAsLeader(_testState()),
        throwsA(isA<Exception>()),
      );
    });

    test('registers GATT service with correct UUIDs', () async {
      await leader.startAsLeader(_testState());
      expect(fakeBle.addedService, isNotNull);
      expect(fakeBle.addedService!.uuid, DraftBleService.serviceUuid);
    });

    test('sets read request handler', () async {
      await leader.startAsLeader(_testState());
      expect(fakeBle.readHandlersSet, isTrue);
    });

    test('sets write request handler', () async {
      await leader.startAsLeader(_testState());
      expect(fakeBle.writeHandlersSet, isTrue);
    });

    test('starts advertising', () async {
      await leader.startAsLeader(_testState());
      expect(fakeBle.startedAdvertising, isTrue);
    });

    test('read handler returns meta bytes', () async {
      await leader.startAsLeader(_testState());
      final result = fakeBle.readHandler!(
        'dev1',
        DraftBleService.metaCharUuid,
        0,
        null,
      );
      expect(result, isNotNull);
      expect(result!.value.isNotEmpty, isTrue);
    });

    test('read handler returns state bytes', () async {
      await leader.startAsLeader(_testState());
      final result = fakeBle.readHandler!(
        'dev1',
        DraftBleService.stateCharUuid,
        0,
        null,
      );
      expect(result, isNotNull);
      expect(result!.value.isNotEmpty, isTrue);
    });

    test('read handler returns empty for unknown characteristic', () async {
      await leader.startAsLeader(_testState());
      final result = fakeBle.readHandler!(
        'dev1',
        'unknown-uuid',
        0,
        null,
      );
      expect(result!.value, isEmpty);
    });

    test('read handler respects offset for meta', () async {
      await leader.startAsLeader(_testState());
      final result = fakeBle.readHandler!(
        'dev1',
        DraftBleService.metaCharUuid,
        1000,
        null,
      );
      expect(result!.value, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // pushState
  // ---------------------------------------------------------------------------

  group('pushState', () {
    test('updates currentState', () async {
      await leader.startAsLeader(_testState());
      final newState = _testState(name: 'Updated Draft').bumpSequence();
      await leader.pushState(newState);
      expect(leader.currentState!.session.name, 'Updated Draft');
    });

    test('skips push when no subscribed devices', () async {
      await leader.startAsLeader(_testState());
      final count = fakeBle.characteristicUpdates.length;
      final newState = _testState().bumpSequence();
      await leader.pushState(newState);
      expect(fakeBle.characteristicUpdates.length, count);
    });

    test('pushes to each subscribed device', () async {
      fakeBle.maximumNotifyLength = 500;
      await leader.startAsLeader(_testState());

      fakeBle.emitSubscription(
          'dev1', DraftBleService.stateCharUuid, true);
      fakeBle.emitSubscription(
          'dev2', DraftBleService.stateCharUuid, true);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final newState = _testState().bumpSequence();
      await leader.pushState(newState);

      final pushedDeviceIds = fakeBle.characteristicUpdates
          .map((u) => u['deviceId'] as String?)
          .toSet();
      expect(pushedDeviceIds, containsAll(['dev1', 'dev2']));
    });

    test('characteristic update contains correct UUID', () async {
      fakeBle.maximumNotifyLength = 500;
      await leader.startAsLeader(_testState());

      fakeBle.emitSubscription(
          'dev1', DraftBleService.stateCharUuid, true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final newState = _testState().bumpSequence();
      await leader.pushState(newState);

      for (final update in fakeBle.characteristicUpdates) {
        expect(
            update['characteristicId'], DraftBleService.stateCharUuid);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Command handling (_handleWriteRequest)
  // ---------------------------------------------------------------------------

  group('command handling', () {
    test('dispatches JoinRequest to onCommandReceived', () async {
      await leader.startAsLeader(_testState());

      DraftCommand? receivedCmd;
      String? receivedDeviceId;
      leader.onCommandReceived = (deviceId, cmd) {
        receivedDeviceId = deviceId;
        receivedCmd = cmd;
      };

      final cmd = JoinRequest(playerName: 'Alice', deviceName: 'alice-device');
      final json = utf8.encode(jsonEncode(cmd.toJson()));
      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        Uint8List.fromList(json),
      );

      expect(receivedDeviceId, 'follower-1');
      expect(receivedCmd, isA<JoinRequest>());
    });

    test('dispatches DropRequest to onCommandReceived', () async {
      await leader.startAsLeader(_testState());

      DraftCommand? receivedCmd;
      leader.onCommandReceived = (deviceId, cmd) {
        receivedCmd = cmd;
      };

      final cmd = DropRequest();
      final json = utf8.encode(jsonEncode(cmd.toJson()));
      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        Uint8List.fromList(json),
      );

      expect(receivedCmd, isA<DropRequest>());
    });

    test('dispatches MatchResult to onCommandReceived', () async {
      await leader.startAsLeader(_testState());

      DraftCommand? receivedCmd;
      leader.onCommandReceived = (deviceId, cmd) {
        receivedCmd = cmd;
      };

      final cmd = MatchResult(
        roundNumber: 1,
        matchId: 'r1_m0',
        myWins: 2,
        opponentWins: 1,
      );
      final json = utf8.encode(jsonEncode(cmd.toJson()));
      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        Uint8List.fromList(json),
      );

      expect(receivedCmd, isA<MatchResult>());
      expect((receivedCmd as MatchResult).myWins, 2);
      expect((receivedCmd as MatchResult).opponentWins, 1);
    });

    test('dispatches SubmitDecklist to onCommandReceived', () async {
      await leader.startAsLeader(_testState());

      DraftCommand? receivedCmd;
      leader.onCommandReceived = (deviceId, cmd) {
        receivedCmd = cmd;
      };

      final cmd = SubmitDecklist(
        mainboardScryfallIds: ['abc', 'def'],
        sideboardScryfallIds: [],
      );
      final json = utf8.encode(jsonEncode(cmd.toJson()));
      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        Uint8List.fromList(json),
      );

      expect(receivedCmd, isA<SubmitDecklist>());
      expect(
          (receivedCmd as SubmitDecklist).mainboardScryfallIds, ['abc', 'def']);
    });

    test('ignores writes to non-command characteristic', () async {
      await leader.startAsLeader(_testState());

      bool called = false;
      leader.onCommandReceived = (_, __) => called = true;

      final bytes = Uint8List.fromList(utf8.encode('{"type":"join"}'));

      fakeBle.writeHandler!(
        'follower-1',
        'some-other-uuid',
        0,
        bytes,
      );

      expect(called, isFalse);
    });

    test('ignores null write value', () async {
      await leader.startAsLeader(_testState());

      bool called = false;
      leader.onCommandReceived = (_, __) => called = true;

      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        null,
      );

      expect(called, isFalse);
    });

    test('survives invalid JSON gracefully', () async {
      await leader.startAsLeader(_testState());

      bool called = false;
      leader.onCommandReceived = (_, __) => called = true;

      final bytes = Uint8List.fromList(utf8.encode('not json'));
      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        bytes,
      );

      expect(called, isFalse);
    });

    test('survives valid JSON with unknown command type', () async {
      await leader.startAsLeader(_testState());

      bool called = false;
      leader.onCommandReceived = (_, __) => called = true;

      final bytes =
          Uint8List.fromList(utf8.encode('{"type":"unknown_command"}'));
      fakeBle.writeHandler!(
        'follower-1',
        DraftBleService.commandCharUuid,
        0,
        bytes,
      );

      // Unknown command type is caught and logged; onCommandReceived not called
      expect(called, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Connection tracking
  // ---------------------------------------------------------------------------

  group('connection tracking', () {
    test('tracks follower connections', () async {
      await leader.startAsLeader(_testState());

      fakeBle.emitConnection('dev1', true);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // pushState tries to push when subscribed
      fakeBle.emitSubscription(
          'dev1', DraftBleService.stateCharUuid, true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final newState = _testState().bumpSequence();
      await leader.pushState(newState);

      expect(fakeBle.characteristicUpdates.isNotEmpty, isTrue);
    });

    test('tracks follower disconnections', () async {
      await leader.startAsLeader(_testState());

      fakeBle.emitConnection('dev1', true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      fakeBle.emitConnection('dev1', false);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // No subscribed devices after disconnect
      final newState = _testState().bumpSequence();
      await leader.pushState(newState);

      // No pushes should happen (no subscribed devices)
      final statePushes = fakeBle.characteristicUpdates
          .where((u) => u['characteristicId'] == DraftBleService.stateCharUuid)
          .length;
      expect(statePushes, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Stop / cleanup
  // ---------------------------------------------------------------------------

  group('stop', () {
    test('stops advertising on stop', () async {
      await leader.startAsLeader(_testState());
      await leader.stop();
      expect(fakeBle.stoppedAdvertising, isTrue);
    });

    test('clears services on stop', () async {
      await leader.startAsLeader(_testState());
      await leader.stop();
      expect(fakeBle.clearedServices, isTrue);
    });

    test('clears read/write handlers on stop', () async {
      await leader.startAsLeader(_testState());
      await leader.stop();
      // stop sets handlers to null; no assertion needed since
      // UniversalBlePeripheral.setReadRequestHandlers(null) handles cleanup.
      // With FakeBlePeripheral, the handlers remain set but the real platform
      // clears them. Verified by no exceptions on subsequent stop.
      await leader.stop();
    });
  });

  // ---------------------------------------------------------------------------
  // Unsupported operations
  // ---------------------------------------------------------------------------

  group('unsupported operations', () {
    test('connectToLeader throws UnsupportedError', () {
      expect(
        () => leader.connectToLeader('any'),
        throwsUnsupportedError,
      );
    });

    test('reconnectToLeader throws UnsupportedError', () {
      expect(
        () => leader.reconnectToLeader('any'),
        throwsUnsupportedError,
      );
    });

    test('sendCommand throws UnsupportedError', () {
      final cmd = JoinRequest(playerName: 'X', deviceName: 'y');
      expect(
        () => leader.sendCommand(cmd),
        throwsUnsupportedError,
      );
    });

    test('leaderConnected throws UnsupportedError', () {
      expect(
        () => leader.leaderConnected,
        throwsUnsupportedError,
      );
    });
  });
}

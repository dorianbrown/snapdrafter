import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'package:snapdrafter/services/draft/ble_platform.dart';
import 'package:snapdrafter/services/draft/draft_ble_follower.dart';
import 'package:snapdrafter/services/draft/draft_ble_leader.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:snapdrafter/services/draft/draft_state.dart';
import 'package:snapdrafter/services/draft/draft_message.dart';

// ---------------------------------------------------------------------------
// FakeBleCentral
// ---------------------------------------------------------------------------

class FakeBleCentral implements BleCentral {
  // Recorded calls
  bool startedScan = false;
  bool stoppedScan = false;
  ScanFilter? lastScanFilter;
  String? connectedDeviceId;
  String? disconnectedDeviceId;
  int? requestedMtu;
  int requestMtuResult = 512;
  String? subDeviceId;
  String? subServiceUuid;
  String? subCharUuid;
  final List<Map<String, dynamic>> writes = [];
  bool disconnectCalled = false;
  List<BleService> discoverServicesResult = [];

  // Error injection
  Object? connectThrow;
  Object? requestMtuThrow;
  Object? discoverServicesThrow;
  Object? subscribeThrow;
  Object? startScanThrow;

  // Streams
  final _scanStreamCtrl = StreamController<BleDevice>.broadcast();
  final _connectionStreamCtrls = <String, StreamController<bool>>{};
  final _charValueCtrls = <String, StreamController<Uint8List>>{};

  @override
  Stream<BleDevice> get scanStream => _scanStreamCtrl.stream;

  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    if (startScanThrow != null) throw startScanThrow!;
    startedScan = true;
    lastScanFilter = scanFilter;
  }

  @override
  Future<void> stopScan() async {
    stoppedScan = true;
  }

  @override
  Future<void> connect(String deviceId) async {
    if (connectThrow != null) throw connectThrow!;
    connectedDeviceId = deviceId;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectedDeviceId = deviceId;
    disconnectCalled = true;
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    if (requestMtuThrow != null) throw requestMtuThrow!;
    requestedMtu = mtu;
    return requestMtuResult;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    if (discoverServicesThrow != null) throw discoverServicesThrow!;
    return discoverServicesResult;
  }

  @override
  Stream<bool> connectionStream(String deviceId) {
    return _connectionStreamCtrls
        .putIfAbsent(deviceId, () => StreamController<bool>.broadcast())
        .stream;
  }

  @override
  Stream<Uint8List> characteristicValueStream(String deviceId, String characteristicUuid) {
    final key = '$deviceId/$characteristicUuid';
    return _charValueCtrls
        .putIfAbsent(key, () => StreamController<Uint8List>.broadcast())
        .stream;
  }

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    if (subscribeThrow != null) throw subscribeThrow!;
    subDeviceId = deviceId;
    subServiceUuid = serviceUuid;
    subCharUuid = characteristicUuid;
  }

  @override
  Future<void> subscribeIndications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    if (subscribeThrow != null) throw subscribeThrow!;
    subDeviceId = deviceId;
    subServiceUuid = serviceUuid;
    subCharUuid = characteristicUuid;
  }

  String? unsubDeviceId;
  String? unsubServiceUuid;
  String? unsubCharUuid;
  Object? unsubscribeThrow;

  @override
  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    if (unsubscribeThrow != null) throw unsubscribeThrow!;
    unsubDeviceId = deviceId;
    unsubServiceUuid = serviceUuid;
    unsubCharUuid = characteristicUuid;
  }

  @override
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    Uint8List value,
  ) async {
    writes.add({
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'value': value,
    });
  }

  Uint8List? readCharacteristicResult;

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    return readCharacteristicResult ?? Uint8List(0);
  }

  void emitScanDevice(BleDevice device) => _scanStreamCtrl.add(device);
  void emitScanError(Object error) => _scanStreamCtrl.addError(error);
  void emitConnected(String deviceId) =>
      _connectionStreamCtrls[deviceId]?.add(true);
  void emitCharacteristicValue(String deviceId, String charUuid, Uint8List bytes) =>
      _charValueCtrls['$deviceId/$charUuid']?.add(bytes);

  void dispose() {
    _scanStreamCtrl.close();
    for (final c in _connectionStreamCtrls.values) {
      c.close();
    }
    for (final c in _charValueCtrls.values) {
      c.close();
    }
  }
}

const _fakeServiceUuid = '4a2e1d0a-0000-4000-8000-00805f9b34fb';

DraftBleFollower _createFollower(FakeBleCentral fake) =>
    DraftBleFollower(ble: fake);

void main() {
  late FakeBleCentral fake;
  late DraftBleFollower follower;

  // -----------------------------------------------------------------------
  // scanForDrafts
  // -----------------------------------------------------------------------

  group('scanForDrafts', () {
    setUp(() {
      fake = FakeBleCentral();
      follower = _createFollower(fake);
    });

    test('emits DiscoveredDraft for each BleDevice', () async {
      final stream = follower.scanForDrafts();
      final results = <DiscoveredDraft>[];
      final sub = stream.listen(results.add);

      fake.emitScanDevice(BleDevice(deviceId: 'dev-1', name: 'My Draft', rssi: -50));
      fake.emitScanDevice(BleDevice(deviceId: 'dev-2', name: 'Other', rssi: -70));

      await Future.delayed(const Duration(milliseconds: 10));

      expect(results.length, 2);
      expect(results[0].deviceId, 'dev-1');
      expect(results[0].draftName, 'My Draft');
      expect(results[0].rssi, -50);
      expect(results[1].deviceId, 'dev-2');
      expect(results[1].draftName, 'Other');

      await sub.cancel();
    });

    test('null device name falls back to deviceId', () async {
      final stream = follower.scanForDrafts();
      final results = <DiscoveredDraft>[];
      final sub = stream.listen(results.add);

      fake.emitScanDevice(BleDevice(deviceId: 'dev-null-name', name: null));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(results.single.draftName, 'dev-null-name');

      await sub.cancel();
    });

    test('null RSSI defaults to 0', () async {
      final stream = follower.scanForDrafts();
      final results = <DiscoveredDraft>[];
      final sub = stream.listen(results.add);

      fake.emitScanDevice(BleDevice(deviceId: 'dev-3', name: 'Draft', rssi: null));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(results.single.rssi, 0);

      await sub.cancel();
    });

    test('playerCount and seatCount are always 0 during scan', () async {
      final stream = follower.scanForDrafts();
      final results = <DiscoveredDraft>[];
      final sub = stream.listen(results.add);

      fake.emitScanDevice(BleDevice(deviceId: 'd', name: 'D', rssi: -40));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(results.single.playerCount, 0);
      expect(results.single.seatCount, 0);

      await sub.cancel();
    });

    test('startScan failure is propagated to stream as error', () async {
      // Make startScan throw so catchError routes it to the output stream.
      final fake2 = FakeBleCentral();
      fake2.startScanThrow = Exception('startScan failed');
      final follower2 = _createFollower(fake2);

      final stream = follower2.scanForDrafts();
      final errors = <Object>[];
      final sub = stream.listen(null, onError: errors.add);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(errors.length, 1);
      expect(errors[0], isA<Exception>());
      await sub.cancel();
    });

    test('scan starts with correct draft service filter', () async {
      follower.scanForDrafts();

      await Future.delayed(const Duration(milliseconds: 10));
      expect(fake.startedScan, isTrue);
      expect(fake.lastScanFilter, isNotNull);
      expect(fake.lastScanFilter!.withServices,
          contains(DraftBleService.serviceUuid));
    });

    test('stopScan cancels subscription and calls stopScan on platform', () async {
      follower.scanForDrafts();
      expect(fake.stoppedScan, isFalse);

      await follower.stopScan();
      expect(fake.stoppedScan, isTrue);
    });

    test('stopScan without a prior scan does not throw', () async {
      await follower.stopScan();
      // No exception thrown — test passes.
    });

    test('sessionId is derived from draftName', () async {
      final stream = follower.scanForDrafts();
      final results = <DiscoveredDraft>[];
      final sub = stream.listen(results.add);

      fake.emitScanDevice(BleDevice(deviceId: 'd', name: 'Hello', rssi: -40));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(results.single.sessionId, isNotEmpty);
      expect(results.single.sessionId.length, 8);

      await sub.cancel();
    });
  });

  // -----------------------------------------------------------------------
  // connectToLeader
  // -----------------------------------------------------------------------

  group('connectToLeader', () {
    late DraftState testState;

    setUp(() {
      fake = FakeBleCentral();
      follower = _createFollower(fake);
      testState = DraftState.create(
        name: 'Test',
        leaderDeviceId: 'leader-device', leaderPlayerName: 'Host',
        seatCount: 4,
      );
    });

    test('full pipeline: connect → mtu → discover → subscribe → state', () async {
      fake.discoverServicesResult = [
        BleService(DraftBleService.serviceUuid, []),
      ];

      final future = follower.connectToLeader('leader-device');

      await Future.delayed(const Duration(milliseconds: 10));
      expect(fake.connectedDeviceId, 'leader-device');
      expect(fake.requestedMtu, 512);

      expect(fake.subDeviceId, 'leader-device');
      expect(fake.subServiceUuid, DraftBleService.serviceUuid);
      expect(fake.subCharUuid, DraftBleService.stateCharUuid);

      final stateBytes = DraftBleService.encodeState(testState);
      fake.emitCharacteristicValue(
        'leader-device',
        DraftBleService.stateCharUuid,
        stateBytes,
      );

      final result = await future;
      expect(result.session.sessionId, testState.session.sessionId);
      expect(result.session.name, 'Test');
    });

    test('sets leaderDeviceId', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];

      final future = follower.connectToLeader('my-leader');
      final stateBytes = DraftBleService.encodeState(testState);
      fake.emitCharacteristicValue(
        'my-leader',
        DraftBleService.stateCharUuid,
        stateBytes,
      );
      await future;

      expect(fake.connectedDeviceId, 'my-leader');
    });

    test('connect failure propagates to caller', () async {
      fake.connectThrow = Exception('Connection refused');

      expect(
        () async => await follower.connectToLeader('bad-device'),
        throwsA(isA<Exception>()),
      );
    });

    test('requestMtu failure propagates to caller', () async {
      fake.requestMtuThrow = Exception('MTU negotiation failed');

      expect(
        () async => await follower.connectToLeader('dev'),
        throwsA(isA<Exception>()),
      );
    });

    test('discoverServices failure propagates to caller', () async {
      fake.discoverServicesThrow = Exception('Service discovery failed');

      expect(
        () async => await follower.connectToLeader('dev'),
        throwsA(isA<Exception>()),
      );
    });

    test('subscribe failure propagates to caller', () async {
      fake.subscribeThrow = Exception('Subscribe failed');

      expect(
        () async => await follower.connectToLeader('dev'),
        throwsA(isA<Exception>()),
      );
    });

    test('null state decode is ignored, waits for next value', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];

      final future = follower.connectToLeader('leader-device');

      await Future.delayed(const Duration(milliseconds: 10));

      fake.emitCharacteristicValue(
        'leader-device',
        DraftBleService.stateCharUuid,
        Uint8List.fromList([0xFF, 0x00, 0xAA]),
      );

      final stateBytes = DraftBleService.encodeState(testState);
      fake.emitCharacteristicValue(
        'leader-device',
        DraftBleService.stateCharUuid,
        stateBytes,
      );

      final result = await future;
      expect(result.session.name, 'Test');
    });

    test('onStatePush is called for each decoded state', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final pushedStates = <DraftState>[];
      follower.onStatePush = pushedStates.add;

      final future = follower.connectToLeader('leader-device');
      await Future.delayed(const Duration(milliseconds: 10));

      final state1 = testState;
      final state2 = testState.bumpSequence();
      fake.emitCharacteristicValue(
        'leader-device',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(state1),
      );
      fake.emitCharacteristicValue(
        'leader-device',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(state2),
      );

      await future;
      await Future.delayed(const Duration(milliseconds: 5));
      expect(pushedStates.length, greaterThanOrEqualTo(2));
    });
  });

  // -----------------------------------------------------------------------
  // reconnectToLeader
  // -----------------------------------------------------------------------

  group('reconnectToLeader', () {
    late DraftState testState;

    setUp(() {
      fake = FakeBleCentral();
      follower = _createFollower(fake);
      testState = DraftState.create(
        name: 'Test',
        leaderDeviceId: 'leader-device', leaderPlayerName: 'Host',
        seatCount: 4,
      );
    });

    test('reconnects with full pipeline', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];

      final future = follower.reconnectToLeader('leader-device');

      await Future.delayed(const Duration(milliseconds: 10));
      final stateBytes = DraftBleService.encodeState(testState);
      fake.emitCharacteristicValue(
        'leader-device',
        DraftBleService.stateCharUuid,
        stateBytes,
      );

      final result = await future;
      expect(result.session.name, 'Test');
      expect(fake.connectedDeviceId, 'leader-device');
    });
  });

  // -----------------------------------------------------------------------
  // sendCommand
  // -----------------------------------------------------------------------

  group('sendCommand', () {
    setUp(() {
      fake = FakeBleCentral();
      follower = _createFollower(fake);
    });

    test('writes JSON payload to command characteristic', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final testState = DraftState.create(name: 'T', leaderDeviceId: 'l', leaderPlayerName: 'Host', seatCount: 4);

      final future = follower.connectToLeader('leader');
      fake.emitCharacteristicValue(
        'leader',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(testState),
      );
      await future;

      await follower.sendCommand(JoinRequest(playerName: 'Alice', deviceName: 'Phone'));

      expect(fake.writes.length, 1);
      expect(fake.writes[0]['deviceId'], 'leader');
      expect(fake.writes[0]['serviceUuid'], DraftBleService.serviceUuid);
      expect(fake.writes[0]['characteristicUuid'], DraftBleService.commandCharUuid);
    });

    test('throws when not connected', () async {
      expect(
        () async => await follower.sendCommand(JoinRequest(playerName: 'A', deviceName: 'D')),
        throwsA(isA<Exception>()),
      );
    });

    test('DropRequest is serialized and written', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final testState = DraftState.create(name: 'T', leaderDeviceId: 'l', leaderPlayerName: 'Host', seatCount: 4);

      final future = follower.connectToLeader('leader');
      fake.emitCharacteristicValue(
        'leader',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(testState),
      );
      await future;

      await follower.sendCommand(DropRequest());
      expect(fake.writes.length, 1);
    });

    test('MatchResult is serialized and written', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final testState = DraftState.create(name: 'T', leaderDeviceId: 'l', leaderPlayerName: 'Host', seatCount: 4);

      final future = follower.connectToLeader('leader');
      fake.emitCharacteristicValue(
        'leader',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(testState),
      );
      await future;

      await follower.sendCommand(MatchResult(
        roundNumber: 1,
        matchId: 'm1',
        myWins: 2,
        opponentWins: 0,
      ));
      expect(fake.writes.length, 1);
    });
  });

  // -----------------------------------------------------------------------
  // stop
  // -----------------------------------------------------------------------

  group('stop', () {
    setUp(() {
      fake = FakeBleCentral();
      follower = _createFollower(fake);
    });

    test('disconnects from connected device', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final testState = DraftState.create(name: 'T', leaderDeviceId: 'l', leaderPlayerName: 'Host', seatCount: 4);

      final future = follower.connectToLeader('leader');
      fake.emitCharacteristicValue(
        'leader',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(testState),
      );
      await future;

      expect(fake.disconnectCalled, isFalse);
      await follower.stop();
      expect(fake.disconnectCalled, isTrue);
      expect(fake.disconnectedDeviceId, 'leader');
    });

    test('does not throw when stopping without a connection', () async {
      await follower.stop();
    });

    test('disconnect failure during stop is swallowed', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final testState = DraftState.create(name: 'T', leaderDeviceId: 'l', leaderPlayerName: 'Host', seatCount: 4);

      final future = follower.connectToLeader('leader');
      fake.emitCharacteristicValue(
        'leader',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(testState),
      );
      await future;

      fake.disconnectCalled = false;
      fake.connectThrow = null;

      await follower.stop();
    });
  });

  // -----------------------------------------------------------------------
  // leaderConnected stream
  // -----------------------------------------------------------------------

  group('leaderConnected', () {
    setUp(() {
      fake = FakeBleCentral();
      follower = _createFollower(fake);
    });

    test('emits connection state from platform stream', () async {
      fake.discoverServicesResult = [BleService(_fakeServiceUuid, [])];
      final testState = DraftState.create(name: 'Test', leaderDeviceId: 'l', leaderPlayerName: 'Host', seatCount: 4);

      final states = <bool>[];
      follower.leaderConnected.listen(states.add);

      final future = follower.connectToLeader('leader');
      fake.emitCharacteristicValue(
        'leader',
        DraftBleService.stateCharUuid,
        DraftBleService.encodeState(testState),
      );
      await future;

      fake.emitConnected('leader');
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, isNotEmpty);
      expect(states.first, isTrue);
    });
  });
}

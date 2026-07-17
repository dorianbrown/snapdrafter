import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
import 'draft_ble_service.dart';
import 'draft_ble_leader.dart';
import 'draft_state.dart';
import 'draft_message.dart';

class DraftBleFollower extends DraftBleService {
  String? _leaderDeviceId;
  final _leaderConnectedCtrl = StreamController<bool>.broadcast();
  StreamSubscription? _scanStreamSub;
  StreamSubscription? _stateValueSub;
  final _streamChunker = BleChunkedStream();

  Stream<bool> get leaderConnected => _leaderConnectedCtrl.stream;

  void Function(DraftState state)? onStatePush;

  Stream<DiscoveredDraft> scanForDrafts() {
    final ctrl = StreamController<DiscoveredDraft>.broadcast();

    _scanStreamSub = UniversalBle.scanStream.listen((BleDevice device) {
      final name = device.name;

      final draftName = name ?? device.deviceId;

      final sessionId = _extractSessionId(draftName);

      ctrl.add(DiscoveredDraft(
        deviceId: device.deviceId,
        draftName: draftName,
        sessionId: sessionId,
        playerCount: 0,
        seatCount: 0,
        rssi: device.rssi ?? 0,
      ));
    });

    UniversalBle.startScan(
      scanFilter: ScanFilter(
        withServices: [DraftBleService.serviceUuid],
      ),
      platformConfig: PlatformConfig(
        android: AndroidOptions(
          scanMode: AndroidScanMode.lowLatency,
          callbackType: [AndroidScanCallbackType.allMatches],
          requestLocationPermission: false,
        ),
      ),
    ).catchError((error) {
      print('[BLE_SCAN] startScan failed: $error');
      ctrl.addError(error);
    });

    return ctrl.stream;
  }

  Future<void> stopScan() async {
    await _scanStreamSub?.cancel();
    _scanStreamSub = null;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  Future<DraftState> connectToLeader(String deviceId) async {
    _leaderDeviceId = deviceId;

    final stateCompleter = Completer<DraftState>();
    _stateValueSub = UniversalBle.characteristicValueStream(
      deviceId,
      DraftBleService.stateCharUuid,
    ).listen((bytes) {
      if (BleChunkedStream.isChunked(bytes)) {
        print('[BLE_FOLLOWER] received chunk (${bytes.length} bytes)');
        _streamChunker.feed(bytes);
        while (_streamChunker.hasCompleteMessage) {
          final assembled = _streamChunker.data;
          if (assembled == null) continue;
          print('[BLE_FOLLOWER] reassembled state notification (${assembled.length} bytes)');
          _processState(assembled, stateCompleter);
        }
      } else {
        print('[BLE_FOLLOWER] received state notification (${bytes.length} bytes)');
        _processState(bytes, stateCompleter);
      }
    });

    print('[BLE_FOLLOWER] connecting to $deviceId...');
    await UniversalBle.connect(deviceId);
    print('[BLE_FOLLOWER] connected to $deviceId');

    final negotiatedMtu = await UniversalBle.requestMtu(deviceId, 512);
    print('[BLE_FOLLOWER] negotiated MTU: $negotiatedMtu');

    UniversalBle.connectionStream(deviceId).listen((connected) {
      _leaderConnectedCtrl.add(connected);
    });

    print('[BLE_FOLLOWER] discovering services...');
    final services = await UniversalBle.discoverServices(deviceId);
    print('[BLE_FOLLOWER] discovered ${services.length} services');

    print('[BLE_FOLLOWER] subscribing to state characteristic...');
    await UniversalBle.subscribeNotifications(
      deviceId,
      DraftBleService.serviceUuid,
      DraftBleService.stateCharUuid,
    );
    print('[BLE_FOLLOWER] subscribed, waiting for initial state...');

    final state = await stateCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('No state notification received from leader'),
    );
    return state;
  }

  void _processState(Uint8List bytes, Completer<DraftState> stateCompleter) {
    final newState = DraftBleService.decodeState(bytes);
    if (newState == null) {
      print('[BLE_FOLLOWER] failed to decode state bytes');
      return;
    }
    if (!stateCompleter.isCompleted) {
      print('[BLE_FOLLOWER] initial state received, seq=${newState.sequenceNumber}');
      stateCompleter.complete(newState);
    }
    onStatePush?.call(newState);
  }

  Future<void> sendCommand(DraftCommand cmd) async {
    if (_leaderDeviceId == null) {
      throw Exception('Not connected to a leader');
    }
    final json = jsonEncode(cmd.toJson());
    final bytes = Uint8List.fromList(utf8.encode(json));
    await UniversalBle.write(
      _leaderDeviceId!,
      DraftBleService.serviceUuid,
      DraftBleService.commandCharUuid,
      bytes,
    );
  }

  String _extractSessionId(String name) {
    int hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Future<void> stop() async {
    await _stateValueSub?.cancel();
    _stateValueSub = null;
    _streamChunker.reset();
    if (_leaderDeviceId != null) {
      try {
        await UniversalBle.disconnect(_leaderDeviceId!);
      } catch (_) {}
    }
    _leaderDeviceId = null;
    await _leaderConnectedCtrl.close();
  }
}

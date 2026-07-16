import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'draft_ble_service.dart';
import 'draft_ble_leader.dart';
import 'draft_state.dart';
import 'draft_message.dart';

class DraftBleFollower extends DraftBleService {
  String? _leaderDeviceId;
  final _leaderConnectedCtrl = StreamController<bool>.broadcast();
  StreamSubscription? _scanStreamSub;
  StreamSubscription? _stateValueSub;

  Stream<bool> get leaderConnected => _leaderConnectedCtrl.stream;

  void Function(DraftState state)? onStatePush;

  Stream<DiscoveredDraft> scanForDrafts() {
    final ctrl = StreamController<DiscoveredDraft>.broadcast();

    _scanStreamSub = UniversalBle.scanStream.listen((BleDevice device) {
      final name = device.name;
      final services = device.services;

      print('[BLE_SCAN] raw device: id=${device.deviceId} '
          'name=$name rssi=${device.rssi} services=$services');

      final draftName = name ?? device.deviceId;

      final sessionId = _extractSessionId(draftName);

      print('[BLE_SCAN]   -> MATCH: $draftName sessionId=$sessionId rssi=${device.rssi}');

      ctrl.add(DiscoveredDraft(
        deviceId: device.deviceId,
        draftName: draftName,
        sessionId: sessionId,
        playerCount: 0,
        seatCount: 0,
        rssi: device.rssi ?? 0,
      ));
    });

    print('[BLE_SCAN] starting scan '
        'withServices=[${DraftBleService.serviceUuid}]');

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

    await UniversalBle.connect(deviceId);

    UniversalBle.connectionStream(deviceId).listen((connected) {
      _leaderConnectedCtrl.add(connected);
    });

    await UniversalBle.discoverServices(deviceId);

    final stateCompleter = Completer<DraftState>();
    _stateValueSub = UniversalBle.characteristicValueStream(
      deviceId,
      DraftBleService.stateCharUuid,
    ).listen((bytes) {
      final newState = DraftBleService.decodeState(bytes);
      if (newState == null) return;
      if (!stateCompleter.isCompleted) {
        stateCompleter.complete(newState);
      }
      onStatePush?.call(newState);
    });

    await UniversalBle.subscribeNotifications(
      deviceId,
      DraftBleService.serviceUuid,
      DraftBleService.stateCharUuid,
    );

    final state = await stateCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('No state notification received from leader'),
    );
    return state;
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
    if (_leaderDeviceId != null) {
      try {
        await UniversalBle.disconnect(_leaderDeviceId!);
      } catch (_) {}
    }
    _leaderDeviceId = null;
    await _leaderConnectedCtrl.close();
  }
}

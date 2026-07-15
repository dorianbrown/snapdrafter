import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'draft_ble_service.dart';
import 'draft_ble_leader.dart';
import 'draft_state.dart';
import 'draft_message.dart';

class DraftBleFollower extends DraftBleService {
  String? _leaderDeviceId;
  final _leaderConnectedCtrl = StreamController<bool>.broadcast();

  Stream<bool> get leaderConnected => _leaderConnectedCtrl.stream;

  void Function(DraftState state)? onStatePush;

  Stream<DiscoveredDraft> scanForDrafts() {
    final ctrl = StreamController<DiscoveredDraft>.broadcast();

    UniversalBle.scanStream.listen((BleDevice device) {
      String draftName = '';
      final nameParts = device.name?.split(': ') ?? [];
      if (nameParts.length >= 2) {
        draftName = nameParts.sublist(1).join(': ');
      } else {
        draftName = device.name ?? 'Unknown Draft';
      }

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
      scanFilter: ScanFilter(withServices: [DraftBleService.serviceUuid]),
    );

    return ctrl.stream;
  }

  Future<void> stopScan() async {
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

    final stateBytes = await UniversalBle.read(
      deviceId,
      DraftBleService.serviceUuid,
      DraftBleService.stateCharUuid,
    );

    final state = DraftBleService.decodeState(stateBytes);
    if (state == null) {
      throw Exception('Failed to decode draft state');
    }

    await UniversalBle.subscribeNotifications(
      deviceId,
      DraftBleService.serviceUuid,
      DraftBleService.stateCharUuid,
    );

    UniversalBle.characteristicValueStream(
      deviceId,
      DraftBleService.stateCharUuid,
    ).listen((bytes) {
      final newState = DraftBleService.decodeState(bytes);
      if (newState != null) {
        onStatePush?.call(newState);
      }
    });

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
    if (_leaderDeviceId != null) {
      try {
        await UniversalBle.disconnect(_leaderDeviceId!);
      } catch (_) {}
    }
    _leaderDeviceId = null;
    await _leaderConnectedCtrl.close();
  }
}

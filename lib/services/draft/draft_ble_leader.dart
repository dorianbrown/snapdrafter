import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'draft_ble_service.dart';
import 'draft_state.dart';
import 'draft_message.dart';

class DiscoveredDraft {
  final String deviceId;
  final String draftName;
  final String sessionId;
  final int playerCount;
  final int seatCount;
  final int rssi;

  const DiscoveredDraft({
    required this.deviceId,
    required this.draftName,
    required this.sessionId,
    required this.playerCount,
    required this.seatCount,
    required this.rssi,
  });
}

class DraftBleLeader extends DraftBleService {
  final _connectedDevices = <String>{};
  final _followerConnectedCtrl = StreamController<String>.broadcast();
  final _followerDisconnectedCtrl = StreamController<String>.broadcast();
  StreamSubscription<BlePeripheralAdvertisingStateChanged>? _advStateSub;

  Uint8List? _currentMetaBytes;
  Uint8List? _currentStateBytes;
  DraftState? _currentState;

  Stream<String> get followerConnected => _followerConnectedCtrl.stream;
  Stream<String> get followerDisconnected => _followerDisconnectedCtrl.stream;

  void Function(String deviceId, DraftCommand command)? onCommandReceived;
  DraftState? get currentState => _currentState;

  Future<void> startAsLeader(DraftState state) async {
    _currentState = state;

    final caps = await UniversalBlePeripheral.getCapabilities();
    print('[BLE_ADV] peripheral capabilities: supportsPeripheralMode=${caps.supportsPeripheralMode}');
    if (!caps.supportsPeripheralMode) {
      throw Exception('Peripheral mode not supported on this device');
    }

    final readiness = await UniversalBlePeripheral.getAvailabilityState();
    print('[BLE_ADV] peripheral readiness: $readiness');
    if (readiness != PeripheralReadinessState.ready) {
      throw Exception('Bluetooth not ready for advertising');
    }

    await UniversalBlePeripheral.addService(
      BlePeripheralService(
        uuid: DraftBleService.serviceUuid,
        primary: true,
        characteristics: [
          BlePeripheralCharacteristic(
            uuid: DraftBleService.metaCharUuid,
            properties: [
              CharacteristicProperty.read,
              CharacteristicProperty.notify,
            ],
            permissions: [PeripheralAttributePermission.readable],
          ),
          BlePeripheralCharacteristic(
            uuid: DraftBleService.stateCharUuid,
            properties: [
              CharacteristicProperty.read,
              CharacteristicProperty.notify,
            ],
            permissions: [PeripheralAttributePermission.readable],
          ),
          BlePeripheralCharacteristic(
            uuid: DraftBleService.commandCharUuid,
            properties: [CharacteristicProperty.write],
            permissions: [PeripheralAttributePermission.writeable],
          ),
        ],
      ),
    );
    print('[BLE_ADV] service added: ${DraftBleService.serviceUuid}');

    UniversalBlePeripheral.setReadRequestHandlers(
      (deviceId, characteristicId, offset, value) {
        if (characteristicId == DraftBleService.metaCharUuid) {
          return PeripheralReadRequestResult(
              value: _currentMetaBytes ?? Uint8List(0));
        }
        if (characteristicId == DraftBleService.stateCharUuid) {
          return PeripheralReadRequestResult(
              value: _currentStateBytes ?? Uint8List(0));
        }
        return PeripheralReadRequestResult(value: Uint8List(0));
      },
    );

    UniversalBlePeripheral.setWriteRequestHandlers(
      (deviceId, characteristicId, offset, value) {
        if (characteristicId == DraftBleService.commandCharUuid &&
            value != null) {
          _handleWriteRequest(deviceId, value);
        }
        return PeripheralWriteRequestResult();
      },
    );

    UniversalBlePeripheral.connectionStateStream.listen((event) {
      if (event.connected) {
        _connectedDevices.add(event.deviceId);
        _followerConnectedCtrl.add(event.deviceId);
      } else {
        _connectedDevices.remove(event.deviceId);
        _followerDisconnectedCtrl.add(event.deviceId);
      }
    });

    _advStateSub = UniversalBlePeripheral.advertisingStateStream.listen((event) {
      print('[BLE_ADV] advertisingStateStream: state=${event.state}, error=${event.error}');
    });

    final localName = state.session.name;
    print('[BLE_ADV] starting advertising: service=${DraftBleService.serviceUuid} localName="$localName"');

    await UniversalBlePeripheral.startAdvertising(
      services: [DraftBleService.serviceUuid],
      localName: localName,
      platformConfig: PeripheralPlatformConfig(
        android: PeripheralAndroidOptions(addServicesInScanResponse: true),
      ),
    );
    print('[BLE_ADV] advertising started successfully');

    _currentMetaBytes = DraftBleService.encodeMeta(state.session);
    _currentStateBytes = DraftBleService.encodeState(state);
  }

  Future<void> pushState(DraftState state) async {
    _currentState = state;
    _currentMetaBytes = DraftBleService.encodeMeta(state.session);
    _currentStateBytes = DraftBleService.encodeState(state);

    try {
      await UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: DraftBleService.metaCharUuid,
        value: _currentMetaBytes!,
      );
    } catch (e) {
      print('Failed to push meta update: $e');
    }

    try {
      await UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: DraftBleService.stateCharUuid,
        value: _currentStateBytes!,
      );
    } catch (e) {
      print('Failed to push state update: $e');
    }
  }

  void _handleWriteRequest(String deviceId, Uint8List value) {
    try {
      final json = utf8.decode(value);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cmd = DraftCommand.fromJson(map);
      onCommandReceived?.call(deviceId, cmd);
    } catch (e) {
      print('Failed to parse command from $deviceId: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _advStateSub?.cancel();
    _advStateSub = null;
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } catch (_) {}
    try {
      await UniversalBlePeripheral.clearServices();
    } catch (_) {}
    await _followerConnectedCtrl.close();
    await _followerDisconnectedCtrl.close();
    _connectedDevices.clear();
    _currentState = null;
  }
}

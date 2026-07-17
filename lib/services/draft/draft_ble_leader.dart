import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
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
  StreamController<String>? _followerConnectedCtrl;
  StreamController<String>? _followerDisconnectedCtrl;
  StreamSubscription<BlePeripheralAdvertisingStateChanged>? _advStateSub;
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>? _charSubStreamSub;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuChangedSub;

  Uint8List? _currentMetaBytes;
  Uint8List? _currentStateBytes;
  DraftState? _currentState;

  final _metaChunker = BleChunkedStream();
  final _stateChunker = BleChunkedStream();

  Stream<String>? get followerConnected => _followerConnectedCtrl?.stream;
  Stream<String>? get followerDisconnected => _followerDisconnectedCtrl?.stream;

  void Function(String deviceId, DraftCommand command)? onCommandReceived;
  DraftState? get currentState => _currentState;

  Future<void> startAsLeader(DraftState state) async {
    _currentState = state;

    _followerConnectedCtrl = StreamController<String>.broadcast();
    _followerDisconnectedCtrl = StreamController<String>.broadcast();

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

    print('[BLE_ADV] adding service...');
    try {
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
    } catch (e) {
      print('[BLE_ADV] addService FAILED: $e');
      rethrow;
    }

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
        _followerConnectedCtrl?.add(event.deviceId);
      } else {
        _connectedDevices.remove(event.deviceId);
        _followerDisconnectedCtrl?.add(event.deviceId);
      }
    });

    _charSubStreamSub = UniversalBlePeripheral.characteristicSubscriptionStream.listen((event) async {
      if (!event.isSubscribed) return;
      final bytes = event.characteristicId == DraftBleService.stateCharUuid
          ? _currentStateBytes
          : event.characteristicId == DraftBleService.metaCharUuid
              ? _currentMetaBytes
              : null;
      if (bytes == null) {
        print('[BLE_ADV] no bytes available for ${event.characteristicId} (stateLen=${_currentStateBytes?.length}, metaLen=${_currentMetaBytes?.length})');
        return;
      }
      await _pushCharacteristicValue(
        characteristicId: event.characteristicId,
        bytes: bytes,
        deviceId: event.deviceId,
      );
    });

    _advStateSub = UniversalBlePeripheral.advertisingStateStream.listen((event) {
      print('[BLE_ADV] advertisingStateStream: state=${event.state}, error=${event.error}');
    });

    _mtuChangedSub = UniversalBlePeripheral.mtuChangedStream.listen((event) {
      _metaChunker.reconfigure(event.mtu);
      _stateChunker.reconfigure(event.mtu);
      print('[BLE_ADV] MTU changed for ${event.deviceId}: ${event.mtu} (chunkPayload=${_stateChunker.maxPayloadPerChunk}, rawLimit=${_stateChunker.maxRawPayload})');
    });

    _currentMetaBytes = DraftBleService.encodeMeta(state.session);
    _currentStateBytes = DraftBleService.encodeState(state);

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

    final registeredServices = await UniversalBlePeripheral.getServices();
    print('[BLE_ADV] registered services on server: $registeredServices');
  }

  Future<void> pushState(DraftState state) async {
    _currentState = state;
    _currentMetaBytes = DraftBleService.encodeMeta(state.session);
    _currentStateBytes = DraftBleService.encodeState(state);

    await _pushCharacteristicValue(
      characteristicId: DraftBleService.metaCharUuid,
      bytes: _currentMetaBytes!,
    );

    await _pushCharacteristicValue(
      characteristicId: DraftBleService.stateCharUuid,
      bytes: _currentStateBytes!,
    );
  }

  Future<void> _pushCharacteristicValue({
    required String characteristicId,
    required Uint8List bytes,
    String? deviceId,
  }) async {
    final isState = characteristicId == DraftBleService.stateCharUuid;
    final chunker = isState ? _stateChunker : _metaChunker;

    if (bytes.length <= chunker.maxRawPayload) {
      print('[BLE_ADV] pushing raw $bytes.length B to${deviceId != null ? " $deviceId" : " all"} on ${characteristicId}');
      try {
        await UniversalBlePeripheral.updateCharacteristicValue(
          characteristicId: characteristicId,
          value: bytes,
          deviceId: deviceId,
        );
      } catch (e) {
        print('[BLE_ADV] FAILED to push value: $e');
      }
      return;
    }

    final chunks = chunker.chunkBytes(bytes);
    print('[BLE_ADV] pushing $chunks.length chunks ($bytes.length B total) to${deviceId != null ? " $deviceId" : " all"} on ${characteristicId}');
    for (var i = 0; i < chunks.length; i++) {
      try {
        await UniversalBlePeripheral.updateCharacteristicValue(
          characteristicId: characteristicId,
          value: chunks[i],
          deviceId: deviceId,
        );
      } catch (e) {
        print('[BLE_ADV] FAILED to push chunk $i/${chunks.length}: $e');
      }
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
    await _charSubStreamSub?.cancel();
    _charSubStreamSub = null;
    await _mtuChangedSub?.cancel();
    _mtuChangedSub = null;
    _metaChunker.reset();
    _stateChunker.reset();
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } catch (_) {}
    try {
      await UniversalBlePeripheral.clearServices();
    } catch (_) {}
    await _followerConnectedCtrl?.close();
    await _followerDisconnectedCtrl?.close();
    _followerConnectedCtrl = null;
    _followerDisconnectedCtrl = null;
    _connectedDevices.clear();
    _currentState = null;
  }
}

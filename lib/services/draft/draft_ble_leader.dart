import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
import 'draft_ble_service.dart';
import 'draft_state.dart';
import 'draft_message.dart';

/// Lightweight info returned from a BLE scan when a draft is discovered.
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

/// BLE peripheral implementation for the draft host.
///
/// Advertises a GATT service with three characteristics:
///   - **Meta** (read/notify): session metadata for scanning followers
///   - **State** (read/notify): full [DraftState] JSON, chunked if > MTU
///   - **Command** (write): incoming [DraftCommand] from followers
///
/// Connected followers receive push notifications of state changes via the
/// state characteristic.
class DraftBleLeader extends DraftBleService {
  final _connectedDevices = <String>{};
  final _subscribedStateDeviceIds = <String>{};
  StreamController<String>? _followerConnectedCtrl;
  StreamController<String>? _followerDisconnectedCtrl;
  StreamSubscription<BlePeripheralAdvertisingStateChanged>? _advStateSub;
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>? _charSubStreamSub;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuChangedSub;
  StreamSubscription<BlePeripheralConnectionStateChanged>? _connStateSub;

  Uint8List? _currentMetaBytes;
  Uint8List? _currentStateBytes;
  DraftState? _currentState;

  final _metaChunker = BleChunkedStream();
  final _stateChunker = BleChunkedStream();
  final _mtuKnownDevices = <String>{};

  Stream<String>? get followerConnected => _followerConnectedCtrl?.stream;
  Stream<String>? get followerDisconnected => _followerDisconnectedCtrl?.stream;

  /// Callback invoked when a follower writes a [DraftCommand] to the
  /// command characteristic.
  @override
  void Function(String deviceId, DraftCommand command)? onCommandReceived;
  DraftState? get currentState => _currentState;

  // -------------------------------------------------------------------------
  // Follower interface — not supported on the leader
  // -------------------------------------------------------------------------

  @override
  Future<DraftState> connectToLeader(String deviceId) =>
      throw UnsupportedError('Leader cannot connect as follower');

  @override
  Future<DraftState> reconnectToLeader(String deviceId) =>
      throw UnsupportedError('Leader cannot reconnect as follower');

  @override
  Future<void> sendCommand(DraftCommand cmd) =>
      throw UnsupportedError('Leader cannot send commands');

  @override
  void Function(DraftState state)? onStatePush;

  @override
  Stream<bool> get leaderConnected =>
      throw UnsupportedError('Leader has no connection stream');

  // -------------------------------------------------------------------------
  // Start advertising
  // -------------------------------------------------------------------------

  /// Registers the GATT service, starts BLE advertising with the draft
  /// name as the local name, and begins accepting connections.
  @override
  Future<void> startAsLeader(DraftState state) async {
    _currentState = state;

    _followerConnectedCtrl = StreamController<String>.broadcast();
    _followerDisconnectedCtrl = StreamController<String>.broadcast();

    final caps = await UniversalBlePeripheral.getCapabilities();
    print('[BLE_ADV] peripheral capabilities: supportsPeripheralMode=${caps.supportsPeripheralMode}');
    if (!caps.supportsPeripheralMode) {
      throw Exception('Peripheral mode not supported on this device');
    }

    await _waitForPeripheralReadiness();

    // Register GATT service with meta (read/notify), state (read/notify),
    // and command (write) characteristics.
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
                CharacteristicProperty.indicate,
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

    // Handle read requests: return the current serialized state/meta bytes.
    UniversalBlePeripheral.setReadRequestHandlers(
      (deviceId, characteristicId, offset, value) {
        if (characteristicId == DraftBleService.metaCharUuid) {
          final bytes = _currentMetaBytes ?? Uint8List(0);
          return PeripheralReadRequestResult(
              value: offset < bytes.length ? bytes.sublist(offset) : Uint8List(0));
        }
        if (characteristicId == DraftBleService.stateCharUuid) {
          final bytes = _currentStateBytes ?? Uint8List(0);
          return PeripheralReadRequestResult(
              value: offset < bytes.length ? bytes.sublist(offset) : Uint8List(0));
        }
        return PeripheralReadRequestResult(value: Uint8List(0));
      },
    );

    // Handle write requests: incoming commands from followers.
    UniversalBlePeripheral.setWriteRequestHandlers(
      (deviceId, characteristicId, offset, value) {
        if (characteristicId == DraftBleService.commandCharUuid &&
            value != null) {
          _handleWriteRequest(deviceId, value);
        }
        return PeripheralWriteRequestResult();
      },
    );

    // Track follower connections vs disconnections.
    _connStateSub = UniversalBlePeripheral.connectionStateStream.listen((event) {
      if (event.connected) {
        _connectedDevices.add(event.deviceId);
        _followerConnectedCtrl?.add(event.deviceId);
        _queryMtuForDevice(event.deviceId);
        print('[BLE_ADV] follower CONNECTED: ${event.deviceId} (total=${_connectedDevices.length})');
      } else {
        _connectedDevices.remove(event.deviceId);
        _followerDisconnectedCtrl?.add(event.deviceId);
        print('[BLE_ADV] follower DISCONNECTED: ${event.deviceId} (total=${_connectedDevices.length})');
      }
    });

    // iOS workaround: When a follower subscribes (or re-subscribes via
    // resubscribeAndReadState on the follower side), we must re-encode the
    // current state fresh. Relying on pre-cached _currentStateBytes can
    // return stale data because:
    //   - iOS peripheral GATT read requests return cached values
    //   - connection-state-dependent early returns in pushState may skip
    //     re-encoding if _connectedDevices is briefly empty
    // Re-encoding guarantees every subscriber always sees the latest state.
    _charSubStreamSub = UniversalBlePeripheral.characteristicSubscriptionStream.listen((event) async {
      if (event.characteristicId == DraftBleService.stateCharUuid) {
        if (event.isSubscribed) {
          _subscribedStateDeviceIds.add(event.deviceId);
        } else {
          _subscribedStateDeviceIds.remove(event.deviceId);
        }
        print('[BLE_ADV] state char ${event.isSubscribed ? "SUBSCRIBED" : "UNSUBSCRIBED"}: ${event.deviceId} (total=${_subscribedStateDeviceIds.length})');
      }
      if (!event.isSubscribed) return;
      if (event.characteristicId == DraftBleService.stateCharUuid && _currentState != null) {
        _currentStateBytes = DraftBleService.encodeState(_currentState!);
      }
      if (event.characteristicId == DraftBleService.metaCharUuid && _currentState != null) {
        _currentMetaBytes = DraftBleService.encodeMeta(_currentState!.session);
      }
      final bytes = event.characteristicId == DraftBleService.stateCharUuid
          ? _currentStateBytes
          : event.characteristicId == DraftBleService.metaCharUuid
              ? _currentMetaBytes
              : null;
      if (bytes == null) {
        print('[BLE_ADV] no bytes available for ${event.characteristicId} (stateLen=${_currentStateBytes?.length}, metaLen=${_currentMetaBytes?.length})');
        return;
      }
      await _queryMtuForDevice(event.deviceId);
      await _pushCharacteristicValue(
        characteristicId: event.characteristicId,
        bytes: bytes,
        deviceId: event.deviceId,
      );
    });

    _advStateSub = UniversalBlePeripheral.advertisingStateStream.listen((event) {
      print('[BLE_ADV] advertisingStateStream: state=${event.state}, error=${event.error}');
    });

    // Reconfigure chunkers when MTU changes for a device.
    _mtuChangedSub = UniversalBlePeripheral.mtuChangedStream.listen((event) {
      _metaChunker.reconfigure(event.mtu);
      _stateChunker.reconfigure(event.mtu);
      print('[BLE_ADV] MTU changed for ${event.deviceId}: ${event.mtu} (chunkPayload=${_stateChunker.maxPayloadPerChunk}, rawLimit=${_stateChunker.maxRawPayload})');
    });

    // Encode initial state and start advertising.
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

  Future<void> _waitForPeripheralReadiness() async {
    const maxAttempts = 20;
    const delay = Duration(milliseconds: 250);

    for (var i = 0; i < maxAttempts; i++) {
      final readiness = await UniversalBlePeripheral.getAvailabilityState();
      print('[BLE_ADV] peripheral readiness (attempt ${i + 1}): $readiness');

      switch (readiness) {
        case PeripheralReadinessState.ready:
          return;
        case PeripheralReadinessState.unsupported:
        case PeripheralReadinessState.unauthorized:
          throw Exception('Bluetooth not available: $readiness');
        case PeripheralReadinessState.unknown:
        case PeripheralReadinessState.bluetoothOff:
          if (i + 1 < maxAttempts) {
            await Future<void>.delayed(delay);
          }
      }
    }

    throw Exception('Bluetooth not ready for advertising (timeout)');
  }

  // -------------------------------------------------------------------------
  // State broadcast
  // -------------------------------------------------------------------------

  /// Re-encodes and pushes the updated [DraftState] to all subscribed
  /// followers via the state characteristic.
  ///
  /// Always re-encodes _currentStateBytes and _currentMetaBytes before any
  /// early return, so that GATT reads, re-subscription handlers, and future
  /// pushes always serve the latest state regardless of connection tracking
  /// glitches.
  @override
  Future<void> pushState(DraftState state) async {
    _currentState = state;
    _currentMetaBytes = DraftBleService.encodeMeta(state.session);
    _currentStateBytes = DraftBleService.encodeState(state);
    print('[BLE_ADV] pushState: seq=${state.sequenceNumber}, players=${state.players.length}, subscribedDevices=${_subscribedStateDeviceIds.length}');
    if (_subscribedStateDeviceIds.isEmpty) {
      print('[BLE_ADV] pushState SKIPPED — no subscribed devices!');
      return;
    }

    for (final deviceId in _subscribedStateDeviceIds.toList()) {
      await _pushCharacteristicValue(
        characteristicId: DraftBleService.stateCharUuid,
        bytes: _currentStateBytes!,
        deviceId: deviceId,
      );
    }
  }

  /// Pushes bytes to a characteristic for either all connected devices or a
  /// specific device. Automatically chunks the payload if it exceeds the
  /// negotiated MTU.
  Future<void> _pushCharacteristicValue({
    required String characteristicId,
    required Uint8List bytes,
    String? deviceId,
  }) async {
    final isState = characteristicId == DraftBleService.stateCharUuid;
    final chunker = isState ? _stateChunker : _metaChunker;

    // Small enough to send in one write.
    if (bytes.length <= chunker.maxRawPayload) {
      print('[BLE_ADV] pushing raw ${bytes.length} B to${deviceId != null ? " $deviceId" : " all"} on ${characteristicId}');
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

    // Chunked transmission.
    final chunks = chunker.chunkBytes(bytes);
    print('[BLE_ADV] pushing ${chunks.length} chunks (${bytes.length} B total) to${deviceId != null ? " $deviceId" : " all"} on $characteristicId');
    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      try {
        await UniversalBlePeripheral.updateCharacteristicValue(
          characteristicId: characteristicId,
          value: chunks[i],
          deviceId: deviceId,
        );
      } catch (e) {
        print('[BLE_ADV] FAILED to push chunk $i/${chunks.length}: $e');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          await UniversalBlePeripheral.updateCharacteristicValue(
            characteristicId: characteristicId,
            value: chunks[i],
            deviceId: deviceId,
          );
        } catch (e2) {
          print('[BLE_ADV] RETRY FAILED for chunk $i: $e2');
        }
      }
    }
  }

  /// Queries the maximum notify length for a device to determine the
  /// effective MTU for chunk calculations.
  Future<void> _queryMtuForDevice(String deviceId) async {
    if (_mtuKnownDevices.contains(deviceId)) return;
    _mtuKnownDevices.add(deviceId);
    try {
      final notifyLen = await UniversalBlePeripheral.getMaximumNotifyLength(deviceId);
      if (notifyLen != null && notifyLen > 0) {
        final mtu = notifyLen + 3;
        _metaChunker.reconfigure(mtu);
        _stateChunker.reconfigure(mtu);
        print('[BLE_ADV] queried MTU for $deviceId: notifyLen=$notifyLen (MTU=$mtu, rawLimit=${_stateChunker.maxRawPayload})');
      }
    } catch (e) {
      print('[BLE_ADV] failed to query MTU for $deviceId: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Incoming commands
  // -------------------------------------------------------------------------

  /// Decodes a JSON payload written by a follower on the command
  /// characteristic and dispatches it via [onCommandReceived].
  void _handleWriteRequest(String deviceId, Uint8List value) {
    try {
      final json = utf8.decode(value);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cmd = DraftCommand.fromJson(map);
      print('[BLE_ADV] command received from $deviceId: type=${cmd.runtimeType}, ${json.length} chars');
      onCommandReceived?.call(deviceId, cmd);
    } catch (e) {
      print('Failed to parse command from $deviceId: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  @override
  Future<void> stop() async {
    await _advStateSub?.cancel();
    _advStateSub = null;
    await _charSubStreamSub?.cancel();
    _charSubStreamSub = null;
    await _mtuChangedSub?.cancel();
    _mtuChangedSub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    _metaChunker.reset();
    _stateChunker.reset();
    _mtuKnownDevices.clear();
    _subscribedStateDeviceIds.clear();
    try {
      UniversalBlePeripheral.setReadRequestHandlers(null);
    } catch (_) {}
    try {
      UniversalBlePeripheral.setWriteRequestHandlers(null);
    } catch (_) {}
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } catch (e) {
      print('[BLE_ADV] stopAdvertising FAILED: $e');
    }
    try {
      await UniversalBlePeripheral.clearServices();
    } catch (e) {
      print('[BLE_ADV] clearServices FAILED: $e');
    }
    await _followerConnectedCtrl?.close();
    await _followerDisconnectedCtrl?.close();
    _followerConnectedCtrl = null;
    _followerDisconnectedCtrl = null;
    _connectedDevices.clear();
    _currentState = null;
  }
}

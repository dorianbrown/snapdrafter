import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
import 'ble_platform.dart';
import 'ble_platform_live.dart';
import 'draft_ble_service.dart';
import 'draft_state.dart';
import 'draft_message.dart';

/// BLE peripheral implementation for the draft host.
///
/// Advertises a GATT service with two characteristics:
///   - **State** (read/notify): full [DraftState] JSON, chunked if > MTU
///   - **Command** (write): incoming [DraftCommand] from followers
///
/// Connected followers receive push notifications of state changes via the
/// state characteristic.
class DraftBleLeader extends DraftBleService {
  final BlePeripheral _ble;

  final _connectedDevices = <String>{};
  final _subscribedStateDeviceIds = <String>{};
  StreamController<String>? _followerConnectedCtrl;
  StreamController<String>? _followerDisconnectedCtrl;
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _charSubStreamSub;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuChangedSub;
  StreamSubscription<BlePeripheralConnectionStateChanged>? _connStateSub;

  Uint8List? _currentStateBytes;

  bool _advertisingPaused = false;
  String? _savedLocalName;

  DraftBleLeader({BlePeripheral? ble}) : _ble = ble ?? LiveBlePeripheral();
  DraftState? _currentState;

  final _stateChunkers = <String, BleChunkedStream>{};
  final _commandChunkers = <String, BleChunkedStream>{};
  final _mtuKnownDevices = <String>{};

  @override
  Stream<String>? get followerConnected => _followerConnectedCtrl?.stream;

  @override
  Stream<String>? get followerDisconnected => _followerDisconnectedCtrl?.stream;

  @override
  int get connectedDeviceCount => _connectedDevices.length;

  bool get isAdvertising => !_advertisingPaused;

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

    final caps = await _ble.getCapabilities();
    _log(
      '[BLE_ADV] peripheral capabilities: supportsPeripheralMode=${caps.supportsPeripheralMode}',
    );
    if (!caps.supportsPeripheralMode) {
      throw Exception('Peripheral mode not supported on this device');
    }

    await _waitForPeripheralReadiness();

    try {
      await _ble.addService(
        BlePeripheralService(
          uuid: DraftBleService.serviceUuid,
          primary: true,
          characteristics: [
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
    } catch (e) {
      _log('[BLE_ADV] addService FAILED: $e');
      rethrow;
    }

    // Handle read requests: return the current serialized state bytes.
    _ble.setReadRequestHandlers((deviceId, characteristicId, offset, value) {
      if (characteristicId == DraftBleService.stateCharUuid) {
        final bytes = _currentStateBytes ?? Uint8List(0);
        return PeripheralReadRequestResult(
          value: offset < bytes.length ? bytes.sublist(offset) : Uint8List(0),
        );
      }
      return PeripheralReadRequestResult(value: Uint8List(0));
    });

    // Handle write requests: incoming commands from followers.
    _ble.setWriteRequestHandlers((deviceId, characteristicId, offset, value) {
      if (characteristicId == DraftBleService.commandCharUuid &&
          value != null) {
        _handleWriteRequest(deviceId, value);
      }
      return PeripheralWriteRequestResult();
    });

    // Track follower connections vs disconnections.
    _connStateSub = _ble.connectionStateStream.listen((event) {
      if (event.connected) {
        _connectedDevices.add(event.deviceId);
        _followerConnectedCtrl?.add(event.deviceId);
        _queryMtuForDevice(event.deviceId);
        _log(
          '[BLE_ADV] follower CONNECTED: ${event.deviceId} (total=${_connectedDevices.length})',
        );
      } else {
        _connectedDevices.remove(event.deviceId);
        _followerDisconnectedCtrl?.add(event.deviceId);
        _subscribedStateDeviceIds.remove(event.deviceId);
        _commandChunkers.remove(event.deviceId);
        _stateChunkers.remove(event.deviceId);
        _mtuKnownDevices.remove(event.deviceId);
        _log(
          '[BLE_ADV] follower DISCONNECTED: ${event.deviceId} (total=${_connectedDevices.length})',
        );
      }
    });

    // iOS workaround: When a follower subscribes (or re-subscribes via
    // resubscribeAndReadState on the follower side), we must re-encode the
    // current state fresh. Relying on pre-cached _currentStateBytes can
    // return stale data because:
    //   - iOS peripheral GATT read requests return cached values
    // Re-encoding guarantees every subscriber always sees the latest state.
    //
    // Subscription events are also the only connection signal available on
    // iOS: CoreBluetooth gives the peripheral no central connect/disconnect
    // callbacks, so connectionStateStream never emits there. Tracking
    // subscriptions keeps _connectedDevices, connectedDeviceCount, and the
    // followerConnected/followerDisconnected streams accurate on both
    // platforms (on Android the connection events already fire, so
    // subscription events only re-confirm existing entries and never
    // double-emit).
    _charSubStreamSub = _ble.characteristicSubscriptionStream.listen((
      event,
    ) async {
      if (event.characteristicId == DraftBleService.stateCharUuid) {
        if (event.isSubscribed) {
          _subscribedStateDeviceIds.add(event.deviceId);
        } else {
          _subscribedStateDeviceIds.remove(event.deviceId);
        }
        _log(
          '[BLE_ADV] state char ${event.isSubscribed ? "SUBSCRIBED" : "UNSUBSCRIBED"}: ${event.deviceId} (total=${_subscribedStateDeviceIds.length})',
        );
      }
      _updateConnectionTracking(event.deviceId, event.isSubscribed);
      if (!event.isSubscribed) return;
      if (event.characteristicId == DraftBleService.stateCharUuid &&
          _currentState != null) {
        _currentStateBytes = DraftBleService.encodeState(_currentState!);
      }
      if (event.characteristicId != DraftBleService.stateCharUuid) return;
      final bytes = _currentStateBytes;
      if (bytes == null) {
        _log(
          '[BLE_ADV] no bytes available for ${event.characteristicId} (stateLen=${_currentStateBytes?.length})',
        );
        return;
      }
      await _queryMtuForDevice(event.deviceId);
      await _pushCharacteristicValue(
        characteristicId: event.characteristicId,
        bytes: bytes,
        deviceId: event.deviceId,
      );
    });

    // Per-device chunkers avoid MTU races between devices.
    _mtuChangedSub = _ble.mtuChangedStream.listen((event) {
      _stateChunkers
          .putIfAbsent(event.deviceId, () => BleChunkedStream())
          .reconfigure(event.mtu);
    });

    // Encode initial state and start advertising.
    _currentStateBytes = DraftBleService.encodeState(state);

    final localName = state.session.name;
    _log(
      '[BLE_ADV] starting advertising: service=${DraftBleService.serviceUuid} localName="$localName"',
    );

    await _ble.startAdvertising(
      services: [DraftBleService.serviceUuid],
      localName: localName,
      platformConfig: PeripheralPlatformConfig(
        android: PeripheralAndroidOptions(addServicesInScanResponse: true),
      ),
    );
    _savedLocalName = localName;
    _advertisingPaused = false;
    _log('[BLE_ADV] advertising started successfully');
  }

  Future<void> _waitForPeripheralReadiness() async {
    const maxAttempts = 20;
    const delay = Duration(milliseconds: 250);
    var printedReady = false;

    for (var i = 0; i < maxAttempts; i++) {
      final readiness = await _ble.getAvailabilityState();
      if (!printedReady) {
        _log('[BLE_ADV] Bluetooth: ${readiness.name}');
        printedReady = readiness == PeripheralReadinessState.ready;
      }

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
  // Advertising lifecycle
  // -------------------------------------------------------------------------

  @override
  Future<void> pauseAdvertising() async {
    if (_advertisingPaused) return;
    _log('[BLE_ADV] pauseAdvertising');
    try {
      await _ble.stopAdvertising();
      _advertisingPaused = true;
    } catch (e) {
      _log('[BLE_ADV] pauseAdvertising FAILED: $e');
    }
  }

  @override
  Future<void> resumeAdvertising() async {
    if (!_advertisingPaused) return;
    _log('[BLE_ADV] resumeAdvertising');
    try {
      await _ble.startAdvertising(
        services: [DraftBleService.serviceUuid],
        localName: _savedLocalName,
        platformConfig: PeripheralPlatformConfig(
          android: PeripheralAndroidOptions(addServicesInScanResponse: true),
        ),
      );
      _advertisingPaused = false;
    } catch (e) {
      _log('[BLE_ADV] resumeAdvertising FAILED: $e');
    }
  }

  // -------------------------------------------------------------------------
  // State broadcast
  // -------------------------------------------------------------------------

  /// Pushes bytes to a characteristic for either all connected devices or a
  /// specific device. Automatically chunks the payload if it exceeds the
  /// negotiated MTU.
  ///
  /// Pushes to all subscribed followers concurrently so one follower's chunk
  /// pacing or a slow link cannot delay the others.
  ///
  /// Targets are derived from subscription events only (not connection
  /// events): iOS peripherals never receive central connect/disconnect
  /// callbacks from CoreBluetooth, so `_connectedDevices` would always be
  /// empty on iOS hosts and every push would be skipped. Subscription events
  /// are reliable on both platforms — Android also emits an unsubscribe for
  /// every characteristic when a central disconnects — and a push to a
  /// stale/removed central fails harmlessly.
  @override
  Future<void> pushState(DraftState state) async {
    _currentState = state;
    _currentStateBytes = DraftBleService.encodeState(state);
    final targets = _subscribedStateDeviceIds.toList();
    _log(
      '[BLE_ADV] pushState: seq=${state.sequenceNumber}, players=${state.players.length}, subscribedDevices=${targets.length}',
    );
    _log('[BLE_ADV] current rounds: ${state.rounds}');
    if (targets.isEmpty) {
      _log('[BLE_ADV] pushState SKIPPED — no subscribed devices!');
      return;
    }

    await Future.wait(
      targets.map(
        (deviceId) => _pushCharacteristicValue(
          characteristicId: DraftBleService.stateCharUuid,
          bytes: _currentStateBytes!,
          deviceId: deviceId,
        ),
      ),
    );
  }

  /// Pushes bytes to a characteristic for either all connected devices or a
  /// specific device. Automatically chunks the payload if it exceeds the
  /// negotiated MTU.
  Future<void> _pushCharacteristicValue({
    required String characteristicId,
    required Uint8List bytes,
    String? deviceId,
  }) async {
    // Per-device chunkers avoid MTU races between devices.
    final chunker = _stateChunkers.putIfAbsent(
      deviceId!,
      () => BleChunkedStream(),
    );

    // Small enough to send in one write.
    if (bytes.length <= chunker.maxRawPayload) {
      try {
        await _ble.updateCharacteristicValue(
          characteristicId: characteristicId,
          value: bytes,
          deviceId: deviceId,
        );
      } catch (e) {
        _log('[BLE_ADV] FAILED to push value: $e');
      }
      return;
    }

    // Chunked transmission.
    final chunks = chunker.chunkBytes(bytes);
    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      try {
        await _ble.updateCharacteristicValue(
          characteristicId: characteristicId,
          value: chunks[i],
          deviceId: deviceId,
        );
      } catch (e) {
        _log('[BLE_ADV] FAILED to push chunk $i/${chunks.length}: $e');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          await _ble.updateCharacteristicValue(
            characteristicId: characteristicId,
            value: chunks[i],
            deviceId: deviceId,
          );
        } catch (e2) {
          _log('[BLE_ADV] RETRY FAILED for chunk $i: $e2');
        }
      }
    }
  }

  /// Tracks device connection state from characteristic subscription events.
  ///
  /// iOS never emits central connect/disconnect events to the peripheral, so
  /// subscriptions are the only reliable connection signal there. A device is
  /// considered connected while it holds an active characteristic
  /// subscription. On Android the connection stream already handles
  /// connect/disconnect; these events only re-confirm existing entries and
  /// never duplicate the follower streams.
  void _updateConnectionTracking(String deviceId, bool isSubscribed) {
    if (isSubscribed) {
      if (_connectedDevices.add(deviceId)) {
        _followerConnectedCtrl?.add(deviceId);
        _log(
          '[BLE_ADV] follower CONNECTED (via subscription): $deviceId (total=${_connectedDevices.length})',
        );
      }
      return;
    }

    if (_connectedDevices.remove(deviceId)) {
      _followerDisconnectedCtrl?.add(deviceId);
      _log(
        '[BLE_ADV] follower DISCONNECTED (no subscriptions left): $deviceId (total=${_connectedDevices.length})',
      );
    }
  }

  /// Queries the maximum notify length for a device to determine the
  /// effective MTU for chunk calculations.
  Future<void> _queryMtuForDevice(String deviceId) async {
    if (_mtuKnownDevices.contains(deviceId)) return;
    _mtuKnownDevices.add(deviceId);
    try {
      final notifyLen = await _ble.getMaximumNotifyLength(deviceId);
      if (notifyLen != null && notifyLen > 0) {
        final mtu = notifyLen + 3;
        _stateChunkers
            .putIfAbsent(deviceId, () => BleChunkedStream())
            .reconfigure(mtu);
        _log(
          '[BLE_ADV] queried MTU for $deviceId: notifyLen=$notifyLen (MTU=$mtu)',
        );
      }
    } catch (e) {
      _log('[BLE_ADV] failed to query MTU for $deviceId: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Incoming commands
  // -------------------------------------------------------------------------

  /// Handles a raw write to the command characteristic, reassembling chunked
  /// command payloads (e.g. large decklists) before dispatch.
  void _handleWriteRequest(String deviceId, Uint8List value) {
    if (BleChunkedStream.isChunked(value)) {
      final chunker = _commandChunkers.putIfAbsent(
        deviceId,
        () => BleChunkedStream(chunkTimeout: const Duration(seconds: 15)),
      );
      chunker.feed(value);
      while (chunker.hasCompleteMessage) {
        final assembled = chunker.data;
        if (assembled == null) continue;
        _dispatchCommand(deviceId, assembled);
      }
      return;
    }
    _dispatchCommand(deviceId, value);
  }

  /// Decodes a JSON payload written by a follower on the command
  /// characteristic and dispatches it via [onCommandReceived].
  void _dispatchCommand(String deviceId, Uint8List value) {
    try {
      final json = utf8.decode(value);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cmd = DraftCommand.fromJson(map);
      _log(
        '[BLE_ADV] command received from $deviceId: type=${cmd.runtimeType}, ${json.length} chars',
      );
      onCommandReceived?.call(deviceId, cmd);
    } catch (e) {
      _log('[BLE_ADV] Failed to parse command from $deviceId: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  @override
  Future<void> stop() async {
    await _charSubStreamSub?.cancel();
    _charSubStreamSub = null;
    await _mtuChangedSub?.cancel();
    _mtuChangedSub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    for (final c in _stateChunkers.values) {
      c.reset();
    }
    for (final c in _commandChunkers.values) {
      c.reset();
    }
    _stateChunkers.clear();
    _commandChunkers.clear();
    _mtuKnownDevices.clear();
    _subscribedStateDeviceIds.clear();
    try {
      _ble.setReadRequestHandlers(null);
    } catch (_) {}
    try {
      _ble.setWriteRequestHandlers(null);
    } catch (_) {}
    try {
      await _ble.stopAdvertising();
    } catch (e) {
      _log('[BLE_ADV] stopAdvertising FAILED: $e');
    }
    try {
      await _ble.clearServices();
    } catch (e) {
      _log('[BLE_ADV] clearServices FAILED: $e');
    }
    await _followerConnectedCtrl?.close();
    await _followerDisconnectedCtrl?.close();
    _followerConnectedCtrl = null;
    _followerDisconnectedCtrl = null;
    _connectedDevices.clear();
    _currentState = null;
    _savedLocalName = null;
    _advertisingPaused = false;
  }
}

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print(msg);
}

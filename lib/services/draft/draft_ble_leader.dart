import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
import 'ble_platform.dart';
import 'ble_platform_live.dart';
import 'draft_ble_service.dart';
import 'draft_link.dart';
import 'draft_protocol.dart';
import 'draft_state.dart';
import 'draft_message.dart';

/// BLE peripheral implementation for the draft host.
///
/// Advertises a GATT service with two characteristics:
///   - **State** (read/notify): binary [DraftProtocol] frames carrying full
///     state snapshots (decklist-free) and periodic ticks.
///   - **Command** (write): incoming [DraftCommand] from followers, including
///     `stateAck` and `resyncRequest` for reliable delivery.
///
/// Each subscribed follower gets a [DraftLinkSession] that keeps one snapshot
/// in flight, coalesces newer snapshots, and retransmits on ACK timeout. A
/// periodic tick lets followers detect missed snapshots and request a resync.
class DraftBleLeader extends DraftBleService {
  final BlePeripheral _ble;

  /// True when this server runs on a relay node rather than the draft host.
  final bool isRelay;

  /// Maximum simultaneous direct links this node will accept.
  final int maxDirectLinks;

  /// When true, `DecklistRequest` commands are forwarded to
  /// [onCommandReceived] instead of being answered locally (relay mode).
  final bool forwardDecklistRequests;

  final _connectedDevices = <String>{};
  final _subscribedStateDeviceIds = <String>{};
  StreamController<String>? _followerConnectedCtrl;
  StreamController<String>? _followerDisconnectedCtrl;
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _charSubStreamSub;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuChangedSub;
  StreamSubscription<BlePeripheralConnectionStateChanged>? _connStateSub;
  StreamSubscription<BlePeripheralAdvertisingStateChanged>? _advStateSub;
  Timer? _tickTimer;
  Timer? _adRefreshTimer;

  Uint8List? _currentStateBytes;

  bool _advertisingPaused = false;
  String? _savedLocalName;
  String? _advertisingError;

  /// Last advertising failure reported by the platform, if any.
  String? get advertisingError => _advertisingError;

  DraftBleLeader({
    BlePeripheral? ble,
    this.isRelay = false,
    this.maxDirectLinks = 4,
    this.forwardDecklistRequests = false,
  }) : _ble = ble ?? LiveBlePeripheral();
  DraftState? _currentState;

  final _stateChunkers = <String, BleChunkedStream>{};
  final _commandChunkers = <String, BleChunkedStream>{};
  final _sessions = <String, DraftLinkSession>{};
  final _mtuKnownDevices = <String>{};

  /// How often a tick frame is broadcast so followers can detect staleness.
  static const tickInterval = Duration(seconds: 2);

  @override
  Stream<String>? get followerConnected => _followerConnectedCtrl?.stream;

  @override
  Stream<String>? get followerDisconnected => _followerDisconnectedCtrl?.stream;

  @override
  int get connectedDeviceCount => _connectedDevices.length;

  bool get isAdvertising => !_advertisingPaused;

  /// Sequence currently advertised to followers.
  int get currentSeq => _currentState?.sequenceNumber ?? 0;

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

  @override
  Future<DraftState?> resubscribeAndReadState() async => null;

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
        _sessions.remove(event.deviceId)?.dispose();
        _mtuKnownDevices.remove(event.deviceId);
        _log(
          '[BLE_ADV] follower DISCONNECTED: ${event.deviceId} (total=${_connectedDevices.length})',
        );
      }
    });

    // Subscription events drive state pushes and are also the only connection
    // signal available on iOS peripherals.
    _charSubStreamSub = _ble.characteristicSubscriptionStream.listen((
      event,
    ) async {
      if (event.characteristicId == DraftBleService.stateCharUuid) {
        if (event.isSubscribed) {
          _subscribedStateDeviceIds.add(event.deviceId);
        } else {
          _subscribedStateDeviceIds.remove(event.deviceId);
        }
        _scheduleAdvertisementRefresh();
        _log(
          '[BLE_ADV] state char ${event.isSubscribed ? "SUBSCRIBED" : "UNSUBSCRIBED"}: ${event.deviceId} (total=${_subscribedStateDeviceIds.length})',
        );
      }
      _updateConnectionTracking(event.deviceId, event.isSubscribed);
      if (event.characteristicId != DraftBleService.stateCharUuid) return;

      if (!event.isSubscribed) {
        _sessions.remove(event.deviceId)?.dispose();
        return;
      }

      await _queryMtuForDevice(event.deviceId);
      final session = _sessionFor(event.deviceId);
      final state = _currentState;
      if (state == null) return;
      _currentStateBytes = DraftBleService.encodeState(state);
      session.sendSnapshot(
        state.sequenceNumber,
        DraftFrame.encodeSnapshot(state.sequenceNumber, _currentStateBytes!),
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

    _tickTimer = Timer.periodic(tickInterval, (_) => _broadcastTick());

    // Advertising failures are reported via callback, not exceptions; without
    // this the host silently advertises nothing.
    _advStateSub = _ble.advertisingStateStream.listen((event) {
      if (event.state == PeripheralAdvertisingState.error) {
        _advertisingError = event.error ?? 'Advertising failed';
        _log('[BLE_ADV] ADVERTISING ERROR: $_advertisingError');
      } else if (event.state == PeripheralAdvertisingState.advertising) {
        _advertisingError = null;
      }
    });

    final localName = DraftProtocol.advertisedName(state.session.name);
    _log(
      '[BLE_ADV] starting advertising: service=${DraftBleService.serviceUuid} localName="$localName"',
    );

    await _ble.startAdvertising(
      services: [DraftBleService.serviceUuid],
      localName: localName,
      manufacturerData: _advertisementData(),
      platformConfig: PeripheralPlatformConfig(
        android: PeripheralAndroidOptions(
          addServicesInScanResponse: true,
          addManufacturerDataInScanResponse: true,
        ),
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
        manufacturerData: _advertisementData(),
        platformConfig: PeripheralPlatformConfig(
          android: PeripheralAndroidOptions(
            addServicesInScanResponse: true,
            addManufacturerDataInScanResponse: true,
          ),
        ),
      );
      _advertisingPaused = false;
    } catch (e) {
      _log('[BLE_ADV] resumeAdvertising FAILED: $e');
    }
  }

  /// Builds the advertisement payload describing this node's role, depth and
  /// remaining direct-link capacity so scanners can pick the best parent.
  ManufacturerData? _advertisementData() {
    final state = _currentState;
    if (state == null) return null;
    final capacity = (maxDirectLinks - _subscribedStateDeviceIds.length).clamp(
      0,
      255,
    );
    return DraftProtocol.buildManufacturerData(
      role: isRelay
          ? DraftAdvertisement.roleRelay
          : DraftAdvertisement.roleLeader,
      depth: isRelay ? 1 : 0,
      capacity: capacity,
      draftId: state.session.sessionId.hashCode & 0xFFFFFFFF,
    );
  }

  /// Re-advertises with an updated capacity after links change.
  void _scheduleAdvertisementRefresh() {
    if (_advertisingPaused ||
        _currentState == null ||
        _savedLocalName == null) {
      return;
    }
    _adRefreshTimer?.cancel();
    _adRefreshTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_advertisingPaused || _currentState == null) return;
      try {
        await _ble.stopAdvertising();
        await _ble.startAdvertising(
          services: [DraftBleService.serviceUuid],
          localName: _savedLocalName,
          manufacturerData: _advertisementData(),
          platformConfig: PeripheralPlatformConfig(
            android: PeripheralAndroidOptions(
              addServicesInScanResponse: true,
              addManufacturerDataInScanResponse: true,
            ),
          ),
        );
      } catch (e) {
        _log('[BLE_ADV] advertisement refresh failed: $e');
      }
    });
  }

  // -------------------------------------------------------------------------
  // State broadcast
  // -------------------------------------------------------------------------

  DraftLinkSession _sessionFor(String deviceId) {
    return _sessions.putIfAbsent(deviceId, () {
      return DraftLinkSession(
        deviceId: deviceId,
        chunker: _stateChunkers.putIfAbsent(deviceId, () => BleChunkedStream()),
        send: (chunk) => _ble.updateCharacteristicValue(
          characteristicId: DraftBleService.stateCharUuid,
          value: chunk,
          deviceId: deviceId,
        ),
        onDead: () => _log('[BLE_ADV] link dead: $deviceId'),
      );
    });
  }

  /// Encodes and pushes the updated [DraftState] to all subscribed followers.
  ///
  /// Decklist contents are omitted; snapshots are enqueued per link and
  /// coalesced so a burst of state changes cannot flood the radio.
  @override
  Future<void> pushState(DraftState state) async {
    _currentState = state;
    _currentStateBytes = DraftBleService.encodeState(state);
    final targets = _subscribedStateDeviceIds.toList();
    _log(
      '[BLE_ADV] pushState: seq=${state.sequenceNumber}, players=${state.players.length}, subscribedDevices=${targets.length}',
    );
    if (targets.isEmpty) {
      _log('[BLE_ADV] pushState SKIPPED — no subscribed devices!');
      return;
    }

    final frame = DraftFrame.encodeSnapshot(
      state.sequenceNumber,
      _currentStateBytes!,
    );
    for (final deviceId in targets) {
      _sessionFor(deviceId).sendSnapshot(state.sequenceNumber, frame);
    }
  }

  void _broadcastTick() {
    final state = _currentState;
    if (state == null) return;
    final tick = DraftFrame.encodeTick(state.sequenceNumber);
    for (final deviceId in _subscribedStateDeviceIds) {
      final session = _sessions[deviceId];
      if (session == null) continue;
      session.sendTick(tick);
    }
  }

  /// Tracks device connection state from characteristic subscription events.
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
    try {
      final notifyLen = await _ble.getMaximumNotifyLength(deviceId);
      if (notifyLen != null && notifyLen > 0) {
        _mtuKnownDevices.add(deviceId);
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
  /// characteristic and dispatches it.
  void _dispatchCommand(String deviceId, Uint8List value) {
    try {
      final json = utf8.decode(value);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cmd = DraftCommand.fromJson(map);
      _log(
        '[BLE_ADV] command received from $deviceId: type=${cmd.runtimeType}',
      );
      switch (cmd) {
        case StateAck(:final seq):
          _sessions[deviceId]?.onAck(seq);
        case ResyncRequest():
          _resendTo(deviceId);
        case DecklistRequest(:final targetDeviceIds):
          if (forwardDecklistRequests) {
            onCommandReceived?.call(deviceId, cmd);
          } else {
            _sendDecklists(deviceId, targetDeviceIds);
          }
        default:
          onCommandReceived?.call(deviceId, cmd);
      }
    } catch (e) {
      _log('[BLE_ADV] Failed to parse command from $deviceId: $e');
    }
  }

  void _resendTo(String deviceId) {
    final state = _currentState;
    if (state == null) return;
    final session = _sessions[deviceId];
    if (session == null) return;
    _log(
      '[BLE_ADV] resync requested by $deviceId (seq=${state.sequenceNumber})',
    );
    session.sendSnapshot(
      state.sequenceNumber,
      DraftFrame.encodeSnapshot(
        state.sequenceNumber,
        _currentStateBytes ?? DraftBleService.encodeState(state),
      ),
    );
  }

  /// Sends an already-encoded reliable frame to a specific subscriber.
  /// Used by relays to forward bulk decklist frames to the child that asked.
  void sendReliableFrame(String deviceId, int seq, Uint8List frame) {
    _sessions[deviceId]?.sendMessage(seq, frame);
  }

  /// Sends decklists for the requested players (or all submitted players when
  /// [requestedIds] is empty). Decklist contents are excluded from live
  /// snapshots, so followers fetch them on demand at the results stage.
  void _sendDecklists(String requesterDeviceId, List<String> requestedIds) {
    final state = _currentState;
    if (state == null) return;
    final session = _sessions[requesterDeviceId];
    if (session == null) return;

    final wanted = requestedIds.toSet();
    final decks = <String, dynamic>{};
    for (final player in state.players) {
      if (player.decklistMainboard == null) continue;
      if (wanted.isNotEmpty && !wanted.contains(player.deviceId)) continue;
      decks[player.deviceId] = {
        'mb': player.decklistMainboard,
        'sb': player.decklistSideboard ?? const <String>[],
      };
    }

    _log(
      '[BLE_ADV] sending decklists to $requesterDeviceId (${decks.length} decks)',
    );
    session.sendMessage(
      state.sequenceNumber,
      DraftFrame.encodeDecklistData(state.sequenceNumber, 'all', {'d': decks}),
    );
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  @override
  Future<void> stop() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _adRefreshTimer?.cancel();
    _adRefreshTimer = null;
    await _charSubStreamSub?.cancel();
    _charSubStreamSub = null;
    await _mtuChangedSub?.cancel();
    _mtuChangedSub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    await _advStateSub?.cancel();
    _advStateSub = null;
    _advertisingError = null;
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
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
    _currentStateBytes = null;
    _savedLocalName = null;
    _advertisingPaused = false;
  }
}

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print(msg);
}

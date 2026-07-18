import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
import 'draft_ble_service.dart';
import 'draft_ble_leader.dart';
import 'draft_state.dart';
import 'draft_message.dart';
import 'ble_platform.dart';
import 'ble_platform_live.dart';

/// BLE central implementation for a draft follower.
///
/// Scans for leaders advertising the draft service UUID, connects,
/// subscribes to state notifications, and sends [DraftCommand] messages
/// via the leader's command characteristic.
///
/// State updates larger than the negotiated MTU are received in chunks
/// and reassembled by [BleChunkedStream].
class DraftBleFollower extends DraftBleService {
  final BleCentral _ble;

  DraftBleFollower({BleCentral? ble}) : _ble = ble ?? LiveBleCentral();

  String? _leaderDeviceId;
  final _leaderConnectedCtrl = StreamController<bool>.broadcast();
  StreamSubscription? _scanStreamSub;
  StreamSubscription? _stateValueSub;
  StreamSubscription? _connectionStreamSub;
  final _streamChunker = BleChunkedStream();

  @override
  Stream<bool> get leaderConnected => _leaderConnectedCtrl.stream;

  /// Callback invoked each time a new [DraftState] is received from the
  /// leader (both the initial state and subsequent push notifications).
  @override
  void Function(DraftState state)? onStatePush;

  // -------------------------------------------------------------------------
  // Leader interface — not supported on the follower
  // -------------------------------------------------------------------------

  @override
  Future<void> startAsLeader(DraftState state) =>
      throw UnsupportedError('Follower cannot host');

  @override
  Future<void> pushState(DraftState state) =>
      throw UnsupportedError('Follower cannot push state');

  @override
  void Function(String deviceId, DraftCommand command)? onCommandReceived;

  // -------------------------------------------------------------------------
  // Scanning
  // -------------------------------------------------------------------------

  /// Begins a BLE scan for devices advertising the draft service UUID.
  /// Returns a stream of [DiscoveredDraft] items.
  Stream<DiscoveredDraft> scanForDrafts() {
    final ctrl = StreamController<DiscoveredDraft>.broadcast();
    final seenDeviceIds = <String>{};

    _scanStreamSub = _ble.scanStream.listen((BleDevice device) {
      if (!seenDeviceIds.add(device.deviceId)) return;

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

    _ble.startScan(
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
      await _ble.stopScan();
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Connection
  // -------------------------------------------------------------------------

  /// Connects to the leader at [deviceId], negotiates MTU, discovers
  /// services, subscribes to state notifications, and awaits the initial
  /// [DraftState] push (with a 5-second timeout).
  @override
  Future<DraftState> connectToLeader(String deviceId) async {
    _leaderDeviceId = deviceId;
    return await _performConnection(deviceId);
  }

  /// Reconnects to a previously connected leader after a BLE disconnect.
  /// Resets internal state and re-runs the full connection flow without
  /// changing the stored [DraftState] locally.
  @override
  Future<DraftState> reconnectToLeader(String deviceId) async {
    await _stateValueSub?.cancel();
    _stateValueSub = null;
    _streamChunker.reset();
    return await _performConnection(deviceId);
  }

  Future<DraftState> _performConnection(String deviceId) async {
    // Listen for state notifications (may arrive in chunks).
    final stateCompleter = Completer<DraftState>();
    _stateValueSub = _ble.characteristicValueStream(
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

    // Subscribe to connection state before connecting so we catch
    // the full lifecycle including connect failures.
    await _connectionStreamSub?.cancel();
    _connectionStreamSub = _ble.connectionStream(deviceId).listen((connected) {
      _leaderConnectedCtrl.add(connected);
    });

    try {
      return await _doConnect(deviceId, stateCompleter).timeout(
        const Duration(seconds: 15),
      );
    } catch (e) {
      // Tear down the connection on any mid-pipeline failure.
      try {
        await _ble.disconnect(deviceId);
      } catch (_) {}
      rethrow;
    }
  }

  Future<DraftState> _doConnect(
    String deviceId,
    Completer<DraftState> stateCompleter,
  ) async {
    print('[BLE_FOLLOWER] connecting to $deviceId...');
    await _ble.connect(deviceId);
    print('[BLE_FOLLOWER] connected to $deviceId');

    final negotiatedMtu = await _ble.requestMtu(deviceId, 512);
    print('[BLE_FOLLOWER] negotiated MTU: $negotiatedMtu');

    print('[BLE_FOLLOWER] discovering services...');
    final services = await _ble.discoverServices(deviceId);
    print('[BLE_FOLLOWER] discovered ${services.length} services');

    print('[BLE_FOLLOWER] subscribing to state characteristic...');
    await _ble.subscribeNotifications(
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

  /// Decodes raw BLE bytes into a [DraftState] and completes the initial
  /// state future on the first call.
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

  // -------------------------------------------------------------------------
  // Command sending
  // -------------------------------------------------------------------------

  /// Serializes a [DraftCommand] to JSON and writes it to the leader's
  /// command characteristic.
  @override
  Future<void> sendCommand(DraftCommand cmd) async {
    if (_leaderDeviceId == null) {
      throw Exception('Not connected to a leader');
    }
    final json = jsonEncode(cmd.toJson());
    final bytes = Uint8List.fromList(utf8.encode(json));
    await _ble.write(
      _leaderDeviceId!,
      DraftBleService.serviceUuid,
      DraftBleService.commandCharUuid,
      bytes,
    );
  }

  /// Reads the current [DraftState] from the leader's state characteristic
  /// via a GATT read (not notification). Used as a fallback when
  /// notification-based state pushes are unreliable (e.g. cross-platform
  /// BLE).
  Future<DraftState?> readCurrentState() async {
    if (_leaderDeviceId == null) return null;
    final bytes = await _ble.readCharacteristic(
      _leaderDeviceId!,
      DraftBleService.serviceUuid,
      DraftBleService.stateCharUuid,
    );
    return DraftBleService.decodeState(bytes);
  }

  /// Derives a short session ID from the draft name by hashing it.
  String _extractSessionId(String name) {
    int hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  @override
  Future<void> stop() async {
    await _stateValueSub?.cancel();
    _stateValueSub = null;
    await _connectionStreamSub?.cancel();
    _connectionStreamSub = null;
    _streamChunker.reset();
    if (_leaderDeviceId != null) {
      try {
        await _ble.disconnect(_leaderDeviceId!);
      } catch (_) {}
    }
    _leaderDeviceId = null;
    await _leaderConnectedCtrl.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'ble_chunked.dart';
import 'draft_ble_service.dart';
import 'draft_protocol.dart';
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
/// Snapshots larger than the negotiated MTU arrive in chunks and are
/// reassembled by [BleChunkedStream]. Every applied snapshot is acknowledged
/// with a `stateAck`; a tick ahead of the applied sequence triggers a
/// `resyncRequest` so a lost snapshot is recovered automatically.
class DraftBleFollower extends DraftBleService {
  final BleCentral _ble;

  DraftBleFollower({BleCentral? ble, this.myDeviceId})
    : _ble = ble ?? LiveBleCentral();

  /// App-level device id used as `src` on outgoing commands and acks.
  final String? myDeviceId;

  String? _leaderDeviceId;
  final _leaderConnectedCtrl = StreamController<bool>.broadcast();
  StreamSubscription? _scanStreamSub;
  StreamSubscription? _stateValueSub;
  StreamSubscription? _connectionStreamSub;
  final _streamChunker = BleChunkedStream();
  final _commandChunker = BleChunkedStream();

  int _appliedSeq = -1;
  Completer<DraftState>? _resyncCompleter;

  @override
  Stream<bool> get leaderConnected => _leaderConnectedCtrl.stream;

  /// BLE device id of the parent (leader or relay) this follower is attached
  /// to, or null when not connected. Used by the debug topology badge.
  String? get parentDeviceId => _leaderDeviceId;

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
  ///
  /// Protocol v2 nodes advertise topology hints in manufacturer data; for
  /// those, one entry per draft is emitted, always pointing at the best parent
  /// (available capacity first, then leader, then shallowest depth, then RSSI).
  /// Legacy/unrecognised advertisers fall back to one entry per device.
  Stream<DiscoveredDraft> scanForDrafts() {
    final ctrl = StreamController<DiscoveredDraft>.broadcast();
    final seenDeviceIds = <String>{};
    final latestByDevice = <String, DiscoveredDraft>{};
    final bestByDraft = <int, DiscoveredDraft>{};

    _scanStreamSub = _ble.scanStream.listen((BleDevice device) {
      final advertisement = DraftProtocol.parseAdvertisement(
        device.manufacturerDataList,
      );

      if (advertisement == null) {
        if (!seenDeviceIds.add(device.deviceId)) return;
        ctrl.add(
          DiscoveredDraft(
            deviceId: device.deviceId,
            draftName: device.name ?? device.deviceId,
            rssi: device.rssi ?? 0,
          ),
        );
        return;
      }

      final candidate = DiscoveredDraft(
        deviceId: device.deviceId,
        draftName: device.name ?? device.deviceId,
        rssi: device.rssi ?? 0,
        advertisement: advertisement,
      );
      latestByDevice[device.deviceId] = candidate;

      final best = _bestParentFor(advertisement.draftId, latestByDevice.values);
      if (best == null) return;
      if (bestByDraft[advertisement.draftId]?.deviceId == best.deviceId) return;
      bestByDraft[advertisement.draftId] = best;
      ctrl.add(best);
    });

    _ble
        .startScan(
          scanFilter: ScanFilter(withServices: [DraftBleService.serviceUuid]),
          platformConfig: PlatformConfig(
            android: AndroidOptions(
              scanMode: AndroidScanMode.lowLatency,
              callbackType: [AndroidScanCallbackType.allMatches],
              requestLocationPermission: false,
            ),
          ),
        )
        .catchError((error) {
          _log('[BLE_SCAN] startScan failed: $error');
          ctrl.addError(error);
        });

    return ctrl.stream;
  }

  /// Picks the best parent among all known advertisers for a draft.
  static DiscoveredDraft? _bestParentFor(
    int draftId,
    Iterable<DiscoveredDraft> candidates,
  ) {
    DiscoveredDraft? best;
    for (final candidate in candidates) {
      if (candidate.draftId != draftId) continue;
      if (best == null || _isBetterParent(candidate, best)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Prefers a parent with free capacity, then the leader over relays, then
  /// shallower depth, then stronger signal.
  static bool _isBetterParent(DiscoveredDraft a, DiscoveredDraft b) {
    final aAvailable = a.capacity > 0;
    final bAvailable = b.capacity > 0;
    if (aAvailable != bAvailable) return aAvailable;
    if (a.isRelay != b.isRelay) return !a.isRelay;
    if (a.depth != b.depth) return a.depth < b.depth;
    return a.rssi > b.rssi;
  }

  Future<void> stopScan() async {
    await _scanStreamSub?.cancel();
    _scanStreamSub = null;
    try {
      await _ble.stopScan();
    } catch (_) {}
  }

  /// Scans briefly and returns the best parent with free capacity, falling
  /// back to the best known candidate when nothing has capacity.
  @override
  Future<DiscoveredDraft?> discoverBestParent({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final ctrl = scanForDrafts();
    DiscoveredDraft? best;
    final completer = Completer<DiscoveredDraft?>();
    final sub = ctrl.listen((draft) {
      if (best == null || _isBetterParent(draft, best!)) {
        best = draft;
      }
      if (draft.capacity > 0 && !completer.isCompleted) {
        completer.complete(best);
      }
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => best);
    } finally {
      await sub.cancel();
      await stopScan();
    }
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
    _leaderDeviceId = deviceId;
    return await _performConnection(deviceId);
  }

  Future<DraftState> _performConnection(String deviceId) async {
    // Listen for state notifications (may arrive in chunks).
    final stateCompleter = Completer<DraftState>();
    _stateValueSub = _ble
        .characteristicValueStream(deviceId, DraftBleService.stateCharUuid)
        .listen(
          (bytes) => _onStateBytes(bytes, stateCompleter),
          onError: (Object e) => _log('[BLE_FOLLOWER] state stream error: $e'),
        );

    // Subscribe to connection state before connecting so we catch
    // the full lifecycle including connect failures.
    await _connectionStreamSub?.cancel();
    _connectionStreamSub = _ble.connectionStream(deviceId).listen((connected) {
      _leaderConnectedCtrl.add(connected);
    });

    try {
      return await _doConnect(
        deviceId,
        stateCompleter,
      ).timeout(const Duration(seconds: 15));
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
    _log('[BLE_FOLLOWER] connecting to $deviceId...');
    await _ble.connect(deviceId);

    final negotiatedMtu = await _ble.requestMtu(deviceId, 512);
    _commandChunker.reconfigure(negotiatedMtu);
    _log('[BLE_FOLLOWER] connected to $deviceId (MTU: $negotiatedMtu)');

    await _ble.discoverServices(deviceId);

    await _ble.subscribeNotifications(
      deviceId,
      DraftBleService.serviceUuid,
      DraftBleService.stateCharUuid,
    );
    _log('[BLE_FOLLOWER] subscribed, waiting for initial state...');

    final state = await stateCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw Exception('No state notification received from leader'),
    );
    return state;
  }

  // -------------------------------------------------------------------------
  // State frames
  // -------------------------------------------------------------------------

  void _onStateBytes(Uint8List bytes, Completer<DraftState> stateCompleter) {
    if (BleChunkedStream.isChunked(bytes)) {
      _streamChunker.feed(bytes);
      while (_streamChunker.hasCompleteMessage) {
        final assembled = _streamChunker.data;
        if (assembled == null) continue;
        _handleFrameBytes(assembled, stateCompleter);
      }
      return;
    }
    if (DraftFrame.isDirectFrame(bytes)) {
      _handleFrameBytes(bytes, stateCompleter);
    }
  }

  void _handleFrameBytes(
    Uint8List bytes,
    Completer<DraftState> stateCompleter,
  ) {
    final frame = DraftFrame.parse(bytes);
    if (frame == null) {
      _log('[BLE_FOLLOWER] malformed frame (${bytes.length} bytes)');
      return;
    }

    if (frame.isTick) {
      _handleTick(frame.seq);
      return;
    }

    if (frame.isSnapshot) {
      _handleSnapshot(frame, stateCompleter);
      return;
    }

    if (frame.isDecklistData) {
      onDecklistData?.call(frame.seq, frame.payload);
      _sendAck(frame.seq);
    }
  }

  void _handleTick(int seq) {
    if (seq > _appliedSeq) {
      _log(
        '[BLE_FOLLOWER] tick seq=$seq ahead of applied=$_appliedSeq, resync',
      );
      requestResync();
    }
  }

  void _handleSnapshot(DraftFrame frame, Completer<DraftState> stateCompleter) {
    final newState = DraftBleService.decodeState(frame.payload);
    if (newState == null) {
      _log('[BLE_FOLLOWER] failed to decode state bytes');
      _sendAck(frame.seq);
      return;
    }

    if (!stateCompleter.isCompleted) {
      _log(
        '[BLE_FOLLOWER] initial state received, seq=${newState.sequenceNumber}',
      );
      stateCompleter.complete(newState);
    }

    if (newState.sequenceNumber > _appliedSeq) {
      _appliedSeq = newState.sequenceNumber;
      onStatePush?.call(newState);
    }

    _resyncCompleter?.complete(newState);
    _resyncCompleter = null;

    // Always acknowledge so the leader can stop retransmitting.
    _sendAck(frame.seq);
  }

  /// Requests decklists from the leader via the command characteristic.
  /// An empty [deviceIds] requests every submitted decklist.
  @override
  Future<void> requestDecklists({List<String> deviceIds = const []}) async {
    final deviceId = _leaderDeviceId;
    if (deviceId == null) {
      throw Exception('Not connected to a leader');
    }
    try {
      await _writeCommand(
        deviceId,
        DecklistRequest(targetDeviceIds: deviceIds, src: myDeviceId ?? ''),
      );
    } catch (e) {
      _log('[BLE_FOLLOWER] decklist request failed: $e');
      rethrow;
    }
  }

  void _sendAck(int seq) {
    final deviceId = _leaderDeviceId;
    if (deviceId == null) return;
    final cmd = StateAck(seq: seq, src: myDeviceId ?? '');
    _writeCommand(deviceId, cmd);
  }

  /// Requests a fresh snapshot from the leader (used after gaps and reconnects).
  @override
  Future<void> requestResync() async {
    final deviceId = _leaderDeviceId;
    if (deviceId == null) return;
    try {
      await _writeCommand(
        deviceId,
        ResyncRequest(appliedSeq: _appliedSeq, src: myDeviceId ?? ''),
      );
    } catch (e) {
      _log('[BLE_FOLLOWER] resync request failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Command sending
  // -------------------------------------------------------------------------

  /// Serializes a [DraftCommand] to JSON and writes it to the leader's
  /// command characteristic.
  ///
  /// Payloads that fit within the negotiated MTU are written as a single
  /// plain JSON write. Larger payloads (e.g. decklists) are chunked with the
  /// same [BleChunkedStream] protocol used for state pushes.
  @override
  Future<void> sendCommand(DraftCommand cmd) async {
    if (_leaderDeviceId == null) {
      throw Exception('Not connected to a leader');
    }
    await _writeCommand(_leaderDeviceId!, cmd);
  }

  Future<void> _writeCommand(String deviceId, DraftCommand cmd) async {
    final json = jsonEncode(cmd.toJson());
    final bytes = Uint8List.fromList(utf8.encode(json));
    _log(
      '[BLE_FOLLOWER] sendCommand: ${cmd.runtimeType} to $deviceId (${json.length} chars)',
    );
    if (bytes.length <= _commandChunker.maxRawPayload) {
      await _ble.write(
        deviceId,
        DraftBleService.serviceUuid,
        DraftBleService.commandCharUuid,
        bytes,
      );
      return;
    }

    final chunks = _commandChunker.chunkBytes(bytes);
    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await _ble.write(
        deviceId,
        DraftBleService.serviceUuid,
        DraftBleService.commandCharUuid,
        chunks[i],
      );
    }
  }

  /// Requests a fresh snapshot from the leader and waits for it to arrive.
  /// Replaces the old unsubscribe/resubscribe dance: the leader keeps
  /// notifications flowing and just retransmits the current snapshot.
  @override
  Future<DraftState?> resubscribeAndReadState() async {
    final deviceId = _leaderDeviceId;
    if (deviceId == null) return null;

    final completer = Completer<DraftState>();
    _resyncCompleter = completer;

    try {
      await _writeCommand(
        deviceId,
        ResyncRequest(appliedSeq: _appliedSeq, src: myDeviceId ?? ''),
      );
    } catch (e) {
      _log('[BLE_FOLLOWER] resync FAILED: $e');
      _resyncCompleter = null;
      return null;
    }

    try {
      return await completer.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _resyncCompleter = null;
      return null;
    }
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
      } catch (e) {
        _log('[BLE_FOLLOWER] disconnect FAILED: $e');
      }
    }
    _leaderDeviceId = null;
    _appliedSeq = -1;
    if (!_leaderConnectedCtrl.isClosed) {
      await _leaderConnectedCtrl.close();
    }
  }
}

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print(msg);
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'draft_state.dart';
import 'draft_message.dart';
import 'draft_protocol.dart';

/// Lightweight info returned from a BLE scan when a draft is discovered.
class DiscoveredDraft {
  final String deviceId;
  final String draftName;
  final int rssi;

  /// Topology hints parsed from the advertisement, when present.
  final DraftAdvertisement? advertisement;

  const DiscoveredDraft({
    required this.deviceId,
    required this.draftName,
    required this.rssi,
    this.advertisement,
  });

  bool get isRelay => advertisement?.isRelay ?? false;
  int get depth => advertisement?.depth ?? 0;
  int get capacity => advertisement?.capacity ?? 0;
  int get draftId => advertisement?.draftId ?? 0;
}

/// Abstract base for the BLE draft service.
///
/// Defines the GATT service UUID, characteristic UUIDs, and JSON
/// serialization helpers used by both the leader (peripheral) and follower
/// (central) implementations.
///
/// Subclasses implement one role (leader or follower) and throw
/// [UnsupportedError] for the opposite role's methods.
abstract class DraftBleService {
  static const serviceUuid = '4a2e1d0a-0000-4000-8000-00805f9b34fb';
  static const stateCharUuid = '4a2e1d0a-0002-4000-8000-00805f9b34fb';
  static const commandCharUuid = '4a2e1d0a-0003-4000-8000-00805f9b34fb';

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  /// Encodes the full [DraftState] for the state characteristic.
  /// May be chunked before transmission if it exceeds the negotiated MTU.
  ///
  /// Decklist contents are omitted by default: live snapshots only carry a
  /// submission flag, and bulk decklists are fetched on demand.
  static Uint8List encodeState(
    DraftState state, {
    bool includeDecklists = false,
  }) {
    final json = jsonEncode(state.toJson(includeDecklists: includeDecklists));
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decodes raw BLE bytes back into a [DraftState].
  /// Returns `null` if the bytes cannot be parsed.
  static DraftState? decodeState(Uint8List bytes) {
    try {
      final json = utf8.decode(bytes);
      final map = jsonDecode(json) as Map<String, dynamic>;
      return DraftState.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Leader (peripheral) interface
  // -------------------------------------------------------------------------

  /// Registers the GATT service and starts BLE advertising so followers
  /// can discover and connect.
  Future<void> startAsLeader(DraftState state);

  /// Encodes and pushes the updated [DraftState] to all connected followers.
  Future<void> pushState(DraftState state);

  /// Callback invoked when a follower writes a [DraftCommand] to the
  /// command characteristic.
  void Function(String deviceId, DraftCommand command)? onCommandReceived;

  // -------------------------------------------------------------------------
  // Follower (central) interface
  // -------------------------------------------------------------------------

  /// Connects to the leader at [deviceId] and returns the initial
  /// [DraftState] received after subscribing to notifications.
  Future<DraftState> connectToLeader(String deviceId);

  /// Reconnects to a previously connected leader after a disconnect.
  Future<DraftState> reconnectToLeader(String deviceId);

  /// Serializes a [DraftCommand] and writes it to the leader's command
  /// characteristic.
  Future<void> sendCommand(DraftCommand cmd);

  /// Callback invoked each time a new [DraftState] is received from the
  /// leader.
  void Function(DraftState state)? onStatePush;

  /// Callback invoked when a bulk decklist payload arrives (followers only).
  void Function(int seq, Uint8List payload)? onDecklistData;

  /// Requests all decklists from the leader (followers only).
  Future<void> requestDecklists() async {}

  /// Stream that emits `true` when connected and `false` on disconnect.
  Stream<bool> get leaderConnected;

  /// Gets the current [DraftState] by forcing a notification via
  /// unsubscribe+resubscribe on the state characteristic. Avoids Android's
  /// BLE GATT read cache that returns stale values.
  Future<DraftState?> resubscribeAndReadState() async => null;

  /// Requests a fresh snapshot from the leader after detecting a gap.
  /// No-op for the leader.
  Future<void> requestResync() async {}

  /// Scans briefly and returns the best parent (leader or relay) for this
  /// draft. Returns null when scanning is unsupported.
  Future<DiscoveredDraft?> discoverBestParent({
    Duration timeout = const Duration(seconds: 3),
  }) async => null;

  // -------------------------------------------------------------------------
  // Leader: advertising lifecycle (default no-ops for follower implementations)
  // -------------------------------------------------------------------------

  int get connectedDeviceCount => 0;

  Stream<String>? get followerConnected => null;
  Stream<String>? get followerDisconnected => null;

  Future<void> pauseAdvertising() async {}

  Future<void> resumeAdvertising() async {}

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /// Stops all BLE activity (advertising/discovery) and releases resources.
  Future<void> stop();
}

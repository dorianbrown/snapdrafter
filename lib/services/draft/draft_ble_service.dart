import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'draft_state.dart';
import 'draft_message.dart';

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
  static const metaCharUuid = '4a2e1d0a-0001-4000-8000-00805f9b34fb';
  static const stateCharUuid = '4a2e1d0a-0002-4000-8000-00805f9b34fb';
  static const commandCharUuid = '4a2e1d0a-0003-4000-8000-00805f9b34fb';

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  /// Encodes session metadata (name, set code, player count, etc.) for the
  /// meta characteristic. Read by scanning followers before connecting.
  static Uint8List encodeMeta(DraftSession session) {
    final json = jsonEncode(session.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Encodes the full [DraftState] for the state characteristic.
  /// May be chunked before transmission if it exceeds the negotiated MTU.
  static Uint8List encodeState(DraftState state) {
    final json = jsonEncode(state.toJson());
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

  /// Stream that emits `true` when connected and `false` on disconnect.
  Stream<bool> get leaderConnected;

  /// Reads the current [DraftState] from the leader's state characteristic
  /// via a GATT read. Used as a fallback for unreliable notification delivery.
  Future<DraftState?> readCurrentState() async => null;

  /// Gets the current [DraftState] by forcing a notification via
  /// unsubscribe+resubscribe on the state characteristic. Avoids Android's
  /// BLE GATT read cache that returns stale values.
  Future<DraftState?> resubscribeAndReadState() async => null;

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

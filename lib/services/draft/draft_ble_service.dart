import 'dart:convert';
import 'dart:typed_data';
import 'draft_state.dart';

/// Abstract base for the BLE draft service.
///
/// Defines the GATT service UUID, characteristic UUIDs, and JSON
/// serialization helpers used by both the leader (peripheral) and follower
/// (central) implementations.
abstract class DraftBleService {
  static const serviceUuid = '4a2e1d0a-0000-4000-8000-00805f9b34fb';
  static const metaCharUuid = '4a2e1d0a-0001-4000-8000-00805f9b34fb';
  static const stateCharUuid = '4a2e1d0a-0002-4000-8000-00805f9b34fb';
  static const commandCharUuid = '4a2e1d0a-0003-4000-8000-00805f9b34fb';

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

  /// Stops all BLE activity (advertising/discovery) and releases resources.
  Future<void> stop();
}

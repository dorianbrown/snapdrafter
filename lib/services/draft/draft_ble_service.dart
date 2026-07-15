import 'dart:convert';
import 'dart:typed_data';
import 'draft_state.dart';

abstract class DraftBleService {
  static const serviceUuid = '4a2e1d0a-0000-4000-8000-00805f9b34fb';
  static const metaCharUuid = '4a2e1d0a-0001-4000-8000-00805f9b34fb';
  static const stateCharUuid = '4a2e1d0a-0002-4000-8000-00805f9b34fb';
  static const commandCharUuid = '4a2e1d0a-0003-4000-8000-00805f9b34fb';

  static Uint8List encodeMeta(DraftSession session) {
    final json = jsonEncode(session.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  static Uint8List encodeState(DraftState state) {
    final json = jsonEncode(state.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  static DraftState? decodeState(Uint8List bytes) {
    try {
      final json = utf8.decode(bytes);
      final map = jsonDecode(json) as Map<String, dynamic>;
      return DraftState.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> stop();
}

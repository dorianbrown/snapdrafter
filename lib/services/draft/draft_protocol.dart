import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Wire protocol v2 for draft BLE sync.
///
/// All downstream traffic (leader/relay -> followers) uses small binary frames
/// on the state characteristic:
///
///   byte 0      frame type
///   bytes 1..4  sequence number (uint32, big endian)
///   bytes 5..   payload (UTF-8 JSON for snapshots/decklists, empty for tick)
///
/// Frames larger than the negotiated payload limit are chunked with
/// [BleChunkedStream]; the assembled bytes are always a complete frame.
/// Frames that fit are written directly. The first byte disambiguates:
/// [BleChunkedStream.chunkedFlag] (0x01) means "feed the chunker",
/// otherwise the bytes are a complete frame.
///
/// Followers acknowledge snapshots with a `stateAck` command carrying the
/// applied sequence number, and request retransmission with `resyncRequest`
/// when a tick reports a sequence ahead of what they have applied.
class DraftProtocol {
  DraftProtocol._();

  /// Bumped on every breaking wire change. Advertised and checked during scan.
  static const int version = 2;

  static const int snapshot = 0x10;
  static const int tick = 0x11;
  static const int decklistData = 0x12;

  /// type(1) + seq(4)
  static const int headerSize = 5;

  /// Manufacturer-data company id used to carry draft topology hints.
  static const int advertisementCompanyId = 0xFFFF;

  /// Maximum bytes for the advertised local name.
  ///
  /// Legacy advertisements cap the packet at 31 bytes. The host advertises
  /// flags (3) + local name (2 + n) + manufacturer data (12), so names longer
  /// than 14 bytes make Android fail with `ADVERTISE_FAILED_DATA_TOO_LARGE`
  /// (and iOS silently drop fields). Keep a conservative budget.
  static const int advertisedNameMaxBytes = 12;

  /// Truncates [name] to [advertisedNameMaxBytes] UTF-8 bytes on a rune
  /// boundary. The full name remains in [DraftState].
  static String advertisedName(String name) {
    final trimmed = name.trim();
    if (utf8.encode(trimmed).length <= advertisedNameMaxBytes) {
      return trimmed;
    }
    final buffer = StringBuffer();
    var used = 0;
    for (final rune in trimmed.runes) {
      final runeBytes = utf8.encode(String.fromCharCode(rune)).length;
      if (used + runeBytes > advertisedNameMaxBytes) break;
      buffer.writeCharCode(rune);
      used += runeBytes;
    }
    return buffer.toString();
  }

  /// Advertisement payload layout:
  ///   version(1) role(1) depth(1) capacity(1) draftId(4)
  static const int advertisementSize = 8;

  static Uint8List encodeAdvertisement({
    required int role,
    required int depth,
    required int capacity,
    required int draftId,
  }) {
    final data = Uint8List(advertisementSize);
    data[0] = version;
    data[1] = role;
    data[2] = depth;
    data[3] = capacity.clamp(0, 255);
    ByteData.sublistView(
      data,
      4,
      advertisementSize,
    ).setUint32(0, draftId, Endian.big);
    return data;
  }

  static ManufacturerData? buildManufacturerData({
    required int role,
    required int depth,
    required int capacity,
    required int draftId,
  }) {
    return ManufacturerData(
      advertisementCompanyId,
      encodeAdvertisement(
        role: role,
        depth: depth,
        capacity: capacity,
        draftId: draftId,
      ),
    );
  }

  static DraftAdvertisement? parseAdvertisement(List<ManufacturerData> list) {
    for (final data in list) {
      if (data.companyId != advertisementCompanyId) continue;
      final payload = data.payload;
      if (payload.length < advertisementSize) continue;
      if (payload[0] != version) continue;
      return DraftAdvertisement(
        role: payload[1],
        depth: payload[2],
        capacity: payload[3],
        draftId: ByteData.sublistView(
          payload,
          4,
          advertisementSize,
        ).getUint32(0, Endian.big),
      );
    }
    return null;
  }
}

/// Topology hints advertised by leaders and relays.
class DraftAdvertisement {
  static const int roleLeader = 0;
  static const int roleRelay = 1;

  final int role;
  final int depth;
  final int capacity;
  final int draftId;

  const DraftAdvertisement({
    required this.role,
    required this.depth,
    required this.capacity,
    required this.draftId,
  });

  bool get isRelay => role == roleRelay;
}

class DraftFrame {
  final int type;
  final int seq;
  final Uint8List payload;

  const DraftFrame({
    required this.type,
    required this.seq,
    required this.payload,
  });

  bool get isSnapshot => type == DraftProtocol.snapshot;
  bool get isTick => type == DraftProtocol.tick;
  bool get isDecklistData => type == DraftProtocol.decklistData;

  /// Parses a complete frame. Returns `null` for malformed input.
  static DraftFrame? parse(Uint8List bytes) {
    if (bytes.length < DraftProtocol.headerSize) return null;
    final type = bytes[0];
    final seq = ByteData.sublistView(
      bytes,
      1,
      DraftProtocol.headerSize,
    ).getUint32(0, Endian.big);
    return DraftFrame(
      type: type,
      seq: seq,
      payload: Uint8List.sublistView(bytes, DraftProtocol.headerSize),
    );
  }

  static Uint8List encode(int type, int seq, [List<int> payload = const []]) {
    final bytes = Uint8List(DraftProtocol.headerSize + payload.length);
    bytes[0] = type;
    ByteData.sublistView(
      bytes,
      1,
      DraftProtocol.headerSize,
    ).setUint32(0, seq, Endian.big);
    bytes.setRange(DraftProtocol.headerSize, bytes.length, payload);
    return bytes;
  }

  static Uint8List encodeTick(int seq) => encode(DraftProtocol.tick, seq);

  static Uint8List encodeSnapshot(int seq, List<int> stateJsonBytes) =>
      encode(DraftProtocol.snapshot, seq, stateJsonBytes);

  static Uint8List encodeDecklistData(
    int seq,
    String targetDeviceId,
    Map<String, dynamic> data,
  ) {
    return encode(
      DraftProtocol.decklistData,
      seq,
      utf8.encode(jsonEncode({'t': targetDeviceId, ...data})),
    );
  }

  /// Returns true when [bytes] is a directly-written frame (not a chunk).
  static bool isDirectFrame(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final type = bytes[0];
    return type == DraftProtocol.snapshot ||
        type == DraftProtocol.tick ||
        type == DraftProtocol.decklistData;
  }
}

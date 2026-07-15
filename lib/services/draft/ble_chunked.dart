import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

class BleChunkedStream {
  static const int headerSize = 8;
  int _maxPayloadPerChunk;

  final Map<int, _ChunkBuffer> _buffers = {};
  int _nextMessageId = 0;
  int? _currentCompleteMessageId;

  BleChunkedStream({int maxPayloadPerChunk = 20})
      : _maxPayloadPerChunk = maxPayloadPerChunk;

  int get maxPayloadPerChunk => _maxPayloadPerChunk;

  void reconfigure(int mtu) {
    _maxPayloadPerChunk = mtu - 3;
  }

  List<Uint8List> chunk(String data) {
    final bytes = utf8.encode(data);
    return chunkBytes(Uint8List.fromList(bytes));
  }

  List<Uint8List> chunkBytes(Uint8List data) {
    final messageId = _nextMessageId++;
    final totalChunks =
        (data.length / _maxPayloadPerChunk).ceil().clamp(1, 65535);
    final chunks = <Uint8List>[];

    for (var i = 0; i < totalChunks; i++) {
      final start = i * _maxPayloadPerChunk;
      final end = min(start + _maxPayloadPerChunk, data.length);
      final payload = data.sublist(start, end);

      final header = ByteData(headerSize);
      header.setInt32(0, messageId, Endian.big);
      header.setInt16(4, i, Endian.big);
      header.setInt16(6, totalChunks, Endian.big);

      final chunk = Uint8List(headerSize + payload.length);
      chunk.setRange(0, headerSize, header.buffer.asUint8List());
      chunk.setRange(headerSize, chunk.length, payload);
      chunks.add(chunk);
    }

    return chunks;
  }

  void feed(Uint8List chunk) {
    if (chunk.length < headerSize) return;

    final header = ByteData.sublistView(chunk, 0, headerSize);
    final messageId = header.getInt32(0, Endian.big);
    final chunkIndex = header.getInt16(4, Endian.big);
    final totalChunks = header.getInt16(6, Endian.big);
    final payload = chunk.sublist(headerSize);

    final buffer = _buffers.putIfAbsent(
      messageId,
      () => _ChunkBuffer(totalChunks),
    );

    buffer.addChunk(chunkIndex, payload);

    if (buffer.isComplete) {
      _currentCompleteMessageId = messageId;
    }
  }

  bool get hasCompleteMessage => _currentCompleteMessageId != null;

  Uint8List? get data {
    if (_currentCompleteMessageId == null) return null;
    final buffer = _buffers.remove(_currentCompleteMessageId);
    _currentCompleteMessageId = null;
    return buffer?.data;
  }

  void reset() {
    _buffers.clear();
    _currentCompleteMessageId = null;
  }
}

class _ChunkBuffer {
  final int totalChunks;
  final List<Uint8List?> _chunks;
  int _received = 0;

  _ChunkBuffer(this.totalChunks) : _chunks = List.filled(totalChunks, null);

  void addChunk(int index, Uint8List data) {
    if (index < 0 || index >= totalChunks) return;
    if (_chunks[index] == null) {
      _chunks[index] = data;
      _received++;
    }
  }

  bool get isComplete => _received == totalChunks;

  Uint8List get data {
    final builder = BytesBuilder();
    for (final chunk in _chunks) {
      if (chunk != null) builder.add(chunk);
    }
    return builder.toBytes();
  }
}

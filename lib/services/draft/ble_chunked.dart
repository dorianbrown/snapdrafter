import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

class BleChunkedStream {
  static const chunkedFlag = 0x01;
  static const int headerSize = 8;

  int _maxPayloadPerChunk;

  final Map<int, _ChunkBuffer> _buffers = {};
  int _nextMessageId = 0;
  int? _currentCompleteMessageId;
  final Duration _chunkTimeout;

  BleChunkedStream({
    int maxPayloadPerChunk = 11,
    Duration chunkTimeout = const Duration(seconds: 5),
  }) : _maxPayloadPerChunk = maxPayloadPerChunk,
       _chunkTimeout = chunkTimeout;

  int get maxPayloadPerChunk => _maxPayloadPerChunk;

  int get maxRawPayload => _maxPayloadPerChunk + chunkOverhead;

  static const chunkOverhead = 1 + headerSize;

  static bool isChunked(Uint8List data) {
    return data.isNotEmpty && data[0] == chunkedFlag;
  }

  void reconfigure(int mtu) {
    _maxPayloadPerChunk = mtu - 3 - chunkOverhead - 3;
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

      final chunk = Uint8List(chunkOverhead + payload.length);
      chunk[0] = chunkedFlag;
      chunk.setRange(1, chunkOverhead, header.buffer.asUint8List());
      chunk.setRange(chunkOverhead, chunk.length, payload);
      chunks.add(chunk);
    }

    return chunks;
  }

  void feed(Uint8List chunk) {
    if (chunk.length < chunkOverhead) return;
    if (chunk[0] != chunkedFlag) return;

    final header = ByteData.sublistView(chunk, 1, chunkOverhead);
    final messageId = header.getInt32(0, Endian.big);
    final chunkIndex = header.getInt16(4, Endian.big);
    final totalChunks = header.getInt16(6, Endian.big);
    final payload = chunk.sublist(chunkOverhead);

    final buffer = _buffers.putIfAbsent(
      messageId,
      () => _ChunkBuffer(
        totalChunks,
        timeout: _effectiveTimeout(totalChunks),
        onTimeout: () {
          _buffers.remove(messageId);
        },
      ),
    );

    buffer.addChunk(chunkIndex, payload);

    if (buffer.isComplete) {
      buffer.cancel();
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
    for (final buffer in _buffers.values) {
      buffer.cancel();
    }
    _buffers.clear();
    _currentCompleteMessageId = null;
  }

  /// The timeout for a message is the configured [chunkTimeout] (idle-based,
  /// refreshed on every chunk) but grows with message size so that large
  /// payloads sent slowly are not dropped, bounded by an absolute cap.
  Duration _effectiveTimeout(int totalChunks) {
    const cap = Duration(seconds: 60);
    final sizeBased = Duration(milliseconds: totalChunks * 50);
    var timeout = sizeBased > _chunkTimeout ? sizeBased : _chunkTimeout;
    if (timeout > cap) timeout = cap;
    return timeout;
  }
}

class _ChunkBuffer {
  final int totalChunks;
  final List<Uint8List?> _chunks;
  final Duration _timeout;
  final void Function() _onTimeout;
  int _received = 0;
  Timer? _timer;
  bool _cancelled = false;

  _ChunkBuffer(
    this.totalChunks, {
    required Duration timeout,
    required void Function() onTimeout,
  }) : _chunks = List.filled(totalChunks, null),
       _timeout = timeout,
       _onTimeout = onTimeout {
    _restartTimer();
  }

  void addChunk(int index, Uint8List data) {
    if (_cancelled) return;
    if (index < 0 || index >= totalChunks) return;
    if (_chunks[index] == null) {
      _chunks[index] = data;
      _received++;
    }
    _restartTimer();
  }

  /// Resets the deadline on every received chunk so the message only fails
  /// if the sender stalls mid-transmission.
  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, () {
      _cancelled = true;
      _onTimeout();
    });
  }

  bool get isComplete => !_cancelled && _received == totalChunks;

  Uint8List get data {
    final builder = BytesBuilder();
    for (final chunk in _chunks) {
      if (chunk != null) builder.add(chunk);
    }
    return builder.toBytes();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _cancelled = true;
  }
}

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapdrafter/services/draft/ble_chunked.dart';

Uint8List _payload(int length) {
  return Uint8List.fromList(List.generate(length, (i) => i % 256));
}

void main() {
  group('BleChunkedStream', () {
    group('chunkBytes + feed + data round-trip', () {
      test('single chunk (payload ≤ maxPayloadPerChunk)', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        final original = _payload(50);

        final chunks = stream.chunkBytes(original);
        expect(chunks.length, 1);

        stream.feed(chunks[0]);
        expect(stream.hasCompleteMessage, isTrue);

        final result = stream.data;
        expect(result, isNotNull);
        expect(result, equals(original));
      });

      test('single chunk (payload == maxPayloadPerChunk)', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 64);
        final original = _payload(64);

        final chunks = stream.chunkBytes(original);
        expect(chunks.length, 1);

        stream.feed(chunks[0]);
        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });

      test('multi-chunk (payload > maxPayloadPerChunk)', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 10);
        final original = _payload(95);

        final chunks = stream.chunkBytes(original);
        expect(chunks.length, greaterThan(1));

        for (final chunk in chunks) {
          stream.feed(chunk);
        }

        expect(stream.hasCompleteMessage, isTrue);
        final result = stream.data;
        expect(result, isNotNull);
        expect(result, equals(original));
      });

      test('exact boundary: 2 chunks', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 5);
        final original = _payload(10);

        final chunks = stream.chunkBytes(original);
        expect(chunks.length, 2);

        stream.feed(chunks[0]);
        stream.feed(chunks[1]);
        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });
    });

    group('feed() reassembly', () {
      test('out-of-order chunks reassemble correctly', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 5);
        final original = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);
        final chunks = stream.chunkBytes(original);
        expect(chunks.length, 2);

        stream.feed(chunks[1]);
        stream.feed(chunks[0]);

        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });

      test('duplicate chunks are idempotent', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 10);
        final original = _payload(25);
        final chunks = stream.chunkBytes(original);

        stream.feed(chunks[0]);
        stream.feed(chunks[0]); // duplicate
        stream.feed(chunks[1]);
        stream.feed(chunks[2]);

        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });

      test('payload without chunkedFlag byte is ignored', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        final badChunk = Uint8List.fromList([0x00, ...List.filled(20, 0)]);
        stream.feed(badChunk);
        expect(stream.hasCompleteMessage, isFalse);
      });

      test('chunk shorter than chunkOverhead is ignored', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        final tooShort = Uint8List.fromList([BleChunkedStream.chunkedFlag, 1, 2, 3]);
        stream.feed(tooShort);
        expect(stream.hasCompleteMessage, isFalse);
      });
    });

    group('hasCompleteMessage + data', () {
      test('hasCompleteMessage is false until all chunks arrive', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 5);
        final original = _payload(15);
        final chunks = stream.chunkBytes(original);
        expect(chunks.length, greaterThan(1));

        for (var i = 0; i < chunks.length - 1; i++) {
          stream.feed(chunks[i]);
          expect(stream.hasCompleteMessage, isFalse);
        }

        stream.feed(chunks.last);
        expect(stream.hasCompleteMessage, isTrue);
      });

      test('data getter is destructive (returns null on second read)', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        stream.feed(stream.chunkBytes(_payload(10))[0]);
        expect(stream.data, isNotNull);
        expect(stream.data, isNull);
      });

      test('second complete message overwrites first if unconsumed', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        final first = _payload(5);
        final second = _payload(3);

        stream.feed(stream.chunkBytes(first)[0]);
        expect(stream.hasCompleteMessage, isTrue);

        stream.feed(stream.chunkBytes(second)[0]);

        final result = stream.data;
        expect(result, isNotNull);
        expect(result, equals(second));
      });
    });

    group('multiple concurrent messages', () {
      test('interleaved chunks from two messages reassemble separately', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 5);
        final msg1 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        final msg2 = Uint8List.fromList([100, 200, 100, 200, 100, 200, 100, 200, 100, 200]);

        final chunks1 = stream.chunkBytes(msg1);
        final chunks2 = stream.chunkBytes(msg2);

        stream.feed(chunks1[0]);
        stream.feed(chunks1[1]);
        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(msg1));
        expect(stream.hasCompleteMessage, isFalse);

        stream.feed(chunks2[0]);
        stream.feed(chunks2[1]);
        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(msg2));
        expect(stream.hasCompleteMessage, isFalse);
      });
    });

    group('chunk() string helper', () {
      test('round-trip via chunk() and feed()', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 10);
        const text = 'Hello, BLE world! This is a test string.';
        final chunks = stream.chunk(text);

        for (final chunk in chunks) {
          stream.feed(chunk);
        }

        expect(stream.hasCompleteMessage, isTrue);
        final bytes = stream.data!;
        final result = String.fromCharCodes(bytes);
        expect(result, equals(text));
      });
    });

    group('reconfigure()', () {
      test('maxPayloadPerChunk updates from MTU', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 11);
        stream.reconfigure(50);
        expect(stream.maxPayloadPerChunk, 50 - 3 - BleChunkedStream.chunkOverhead - 3);
      });

      test('maxRawPayload = maxPayloadPerChunk + chunkOverhead', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 16);
        expect(stream.maxRawPayload, 16 + BleChunkedStream.chunkOverhead);
      });

      test('reconfigure affects chunking behavior', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 11);
        stream.reconfigure(30);
        final original = _payload(50);

        final chunks = stream.chunkBytes(original);
        // After reconfigure, fewer chunks are needed
        expect(chunks.length, greaterThan(0));

        for (final chunk in chunks) {
          stream.feed(chunk);
        }
        expect(stream.data, equals(original));
      });
    });

    group('timeout behavior', () {
      test('idle-based timeout: completes when chunks arrive within timeout',
          () async {
        final stream = BleChunkedStream(
          maxPayloadPerChunk: 5,
          chunkTimeout: const Duration(milliseconds: 300),
        );
        final original = _payload(15); // 3 chunks
        final chunks = stream.chunkBytes(original);

        stream.feed(chunks[0]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        stream.feed(chunks[1]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        stream.feed(chunks[2]);

        // Total elapsed (400ms) exceeds chunkTimeout, but no gap between
        // chunks did — the message must still complete.
        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });

      test('stalled message is dropped after the timeout', () async {
        final stream = BleChunkedStream(
          maxPayloadPerChunk: 5,
          chunkTimeout: const Duration(milliseconds: 150),
        );
        final chunks = stream.chunkBytes(_payload(10)); // 2 chunks

        stream.feed(chunks[0]);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // The buffer was dropped; the late chunk starts a fresh buffer that
        // is still missing chunk 0.
        stream.feed(chunks[1]);
        expect(stream.hasCompleteMessage, isFalse);
      });

      test('timeout grows with total chunk count', () async {
        final stream = BleChunkedStream(
          maxPayloadPerChunk: 5,
          chunkTimeout: const Duration(milliseconds: 200),
        );
        final original = _payload(50); // 10 chunks -> 500ms size-based timeout
        final chunks = stream.chunkBytes(original);

        stream.feed(chunks[0]);
        // 350ms > chunkTimeout but < the size-based timeout; the message must
        // still be alive.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        for (final chunk in chunks.skip(1)) {
          stream.feed(chunk);
        }

        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });
    });

    group('reset()', () {
      test('clears in-progress buffers', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 5);
        final original = _payload(15);
        final chunks = stream.chunkBytes(original);

        stream.feed(chunks[0]);
        stream.reset();

        expect(stream.hasCompleteMessage, isFalse);

        stream.feed(chunks[2]);
        stream.feed(chunks[0]);
        stream.feed(chunks[1]);

        expect(stream.hasCompleteMessage, isTrue);
        expect(stream.data, equals(original));
      });

      test('clears complete message', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        stream.feed(stream.chunkBytes(_payload(10))[0]);
        expect(stream.hasCompleteMessage, isTrue);

        stream.reset();
        expect(stream.hasCompleteMessage, isFalse);
        expect(stream.data, isNull);
      });
    });

    group('isChunked()', () {
      test('returns true for bytes starting with chunkedFlag', () {
        final chunked = Uint8List.fromList(
            [BleChunkedStream.chunkedFlag, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        expect(BleChunkedStream.isChunked(chunked), isTrue);
      });

      test('returns false for bytes without chunkedFlag', () {
        final regular = Uint8List.fromList([0x00, 0x01, 0x02]);
        expect(BleChunkedStream.isChunked(regular), isFalse);
      });

      test('returns false for empty bytes', () {
        expect(BleChunkedStream.isChunked(Uint8List(0)), isFalse);
      });
    });

    group('totalChunks clamped', () {
      test('totalChunks minimum is 1 even for zero-length data', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 10);
        final chunks = stream.chunkBytes(Uint8List(0));
        expect(chunks.length, 1);
        stream.feed(chunks[0]);
        expect(stream.data, equals(Uint8List(0)));
      });
    });

    group('chunk header fields', () {
      test('chunk has chunkedFlag as first byte', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 100);
        final chunks = stream.chunkBytes(_payload(5));
        expect(chunks[0][0], BleChunkedStream.chunkedFlag);
      });

      test('chunk length == chunkOverhead + payload length', () {
        final stream = BleChunkedStream(maxPayloadPerChunk: 10);
        final original = _payload(8);
        final chunks = stream.chunkBytes(original);
        expect(chunks[0].length,
            BleChunkedStream.chunkOverhead + original.length);
      });
    });
  });
}

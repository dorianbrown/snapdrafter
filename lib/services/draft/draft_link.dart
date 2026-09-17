import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ble_chunked.dart';

/// Reliable downstream link to a single follower.
///
/// Owns a [BleChunkedStream] for MTU-aware chunking and a tiny send state
/// machine that:
///   - keeps at most one snapshot in flight per link,
///   - coalesces newer snapshots into a single pending slot,
///   - retransmits on ACK timeout with exponential-ish backoff,
///   - declares the link dead after [maxRetries] failed attempts.
///
/// Ticks are best-effort and skipped while a snapshot transfer is active.
class DraftLinkSession {
  DraftLinkSession({
    required this.deviceId,
    required this.send,
    required this.chunker,
    this.chunkPacing = const Duration(milliseconds: 30),
    this.ackTimeout = const Duration(milliseconds: 1200),
    this.maxRetries = 4,
    this.onDead,
    this.onAcked,
  });

  final String deviceId;

  /// Sends one already-chunked payload to this device.
  final Future<void> Function(Uint8List chunk) send;

  final BleChunkedStream chunker;
  final Duration chunkPacing;
  final Duration ackTimeout;
  final int maxRetries;
  final void Function()? onDead;
  final void Function(int seq)? onAcked;

  _Outgoing? _inFlight;
  _Outgoing? _pending;
  final Queue<_Outgoing> _messageQueue = Queue<_Outgoing>();
  Timer? _ackTimer;
  int _retries = 0;
  bool _pumping = false;
  bool _dead = false;
  bool _disposed = false;

  bool get isDead => _dead;

  /// Sequence currently awaiting an ACK, if any.
  int? get inFlightSeq => _inFlight?.seq;

  /// Queues a snapshot frame. Replaces any previously queued snapshot.
  void sendSnapshot(int seq, Uint8List frameBytes) {
    if (_disposed) return;
    if (_dead) {
      // A resync request or a fresh state change can revive the link; the
      // radio may still be up even if our retries were exhausted.
      _dead = false;
      _retries = 0;
    }
    _pending = _Outgoing(seq, frameBytes, coalescable: true);
    _pump();
  }

  /// Queues a non-coalescing reliable message (e.g. decklist data). Messages
  /// are delivered in order after any pending snapshot.
  void sendMessage(int seq, Uint8List frameBytes) {
    if (_disposed) return;
    if (_dead) {
      _dead = false;
      _retries = 0;
    }
    _messageQueue.add(_Outgoing(seq, frameBytes, coalescable: false));
    _pump();
  }

  /// Best-effort tick; dropped when the link is busy.
  Future<void> sendTick(Uint8List tickBytes) async {
    if (_dead || _disposed) return;
    if (_pumping ||
        _inFlight != null ||
        _pending != null ||
        _messageQueue.isNotEmpty) {
      return;
    }
    try {
      await send(tickBytes);
    } catch (e) {
      _log('tick send failed for $deviceId: $e');
    }
  }

  void onAck(int seq) {
    if (_inFlight?.seq == seq) {
      _ackTimer?.cancel();
      _ackTimer = null;
      final acked = _inFlight!.seq;
      _inFlight = null;
      _retries = 0;
      onAcked?.call(acked);
      _pump();
    }
  }

  void dispose() {
    _disposed = true;
    _ackTimer?.cancel();
    _ackTimer = null;
    _inFlight = null;
    _pending = null;
    _messageQueue.clear();
  }

  void _pump() {
    if (_pumping || _dead || _disposed) return;
    if (_inFlight != null) return;
    if (_pending == null && _messageQueue.isEmpty) return;
    _pumping = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    final outgoing = _pending ?? _nextQueued();
    if (outgoing == null) {
      _pumping = false;
      return;
    }
    _pending = null;
    _inFlight = outgoing;
    _retries = 0;
    await _transmit(outgoing);
    if (_dead || _disposed) {
      _pumping = false;
      return;
    }
    _pumping = false;
    _armAckTimer();
  }

  _Outgoing? _nextQueued() {
    if (_messageQueue.isEmpty) return null;
    return _messageQueue.removeFirst();
  }

  Future<void> _transmit(_Outgoing outgoing) async {
    final List<Uint8List> chunks;
    if (outgoing.frameBytes.length <= chunker.maxRawPayload) {
      chunks = [outgoing.frameBytes];
    } else {
      chunks = chunker.chunkBytes(outgoing.frameBytes);
    }

    for (var i = 0; i < chunks.length; i++) {
      if (_dead || _disposed) return;
      if (i > 0) {
        await Future<void>.delayed(chunkPacing);
      }
      try {
        await send(chunks[i]);
      } catch (e) {
        _log('chunk $i/${chunks.length} send failed for $deviceId: $e');
        return;
      }
    }
  }

  void _armAckTimer() {
    _ackTimer?.cancel();
    _ackTimer = Timer(ackTimeout, () {
      if (_dead || _disposed || _inFlight == null) return;
      _retries++;
      if (_retries > maxRetries) {
        _dead = true;
        _inFlight = null;
        _pending = null;
        _log('link to $deviceId declared dead after $_retries retries');
        onDead?.call();
        return;
      }
      // Retransmit non-coalescing messages; snapshots are superseded by any
      // newer pending snapshot, so they are not requeued.
      if (_inFlight != null && !_inFlight!.coalescable) {
        _messageQueue.addFirst(_inFlight!);
      }
      _inFlight = null;
      _pump();
    });
  }
}

class _Outgoing {
  final int seq;
  final Uint8List frameBytes;
  final bool coalescable;

  _Outgoing(this.seq, this.frameBytes, {required this.coalescable});
}

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print('[DRAFT_LINK] $msg');
}

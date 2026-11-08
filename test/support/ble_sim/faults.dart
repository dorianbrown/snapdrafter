import 'dart:math';

/// Deterministic fault injection for the BLE simulator.
///
/// Counters are keyed by node id and decremented before failing, so a test can
/// say "fail the next advertising start on the host" or "drop the next three
/// writes from p3" without depending on wall-clock timing.
class BleSimFaults {
  BleSimFaults({int? seed}) : _random = Random(seed);

  final Random _random;

  final Map<String, int> _advertisingFailures = {};
  final Map<String, int> _connectFailures = {};
  final Map<String, int> _subscribeFailures = {};
  final Map<String, int> _writeFailures = {};
  final Map<String, int> _mtuFailures = {};

  /// When set, every MTU request returns this value (for low-MTU tests).
  int? forcedMtu;

  /// Deterministic packet mutations. A value of 0 disables the mutation.
  int duplicateEvery = 0;
  int reorderEvery = 0;
  int corruptEvery = 0;

  int _duplicateCounter = 0;
  int _reorderCounter = 0;
  int _corruptCounter = 0;

  int duplicatedPackets = 0;
  int reorderedPackets = 0;
  int corruptedPackets = 0;

  /// Number of injected failures consumed by the network.
  int injectedFailures = 0;

  void failNextAdvertising(String nodeId, [int count = 1]) {
    _advertisingFailures[nodeId] = (_advertisingFailures[nodeId] ?? 0) + count;
  }

  void failNextConnect(String nodeId, [int count = 1]) {
    _connectFailures[nodeId] = (_connectFailures[nodeId] ?? 0) + count;
  }

  void failNextSubscribe(String nodeId, [int count = 1]) {
    _subscribeFailures[nodeId] = (_subscribeFailures[nodeId] ?? 0) + count;
  }

  void failNextWrite(String nodeId, [int count = 1]) {
    _writeFailures[nodeId] = (_writeFailures[nodeId] ?? 0) + count;
  }

  void failNextMtu(String nodeId, [int count = 1]) {
    _mtuFailures[nodeId] = (_mtuFailures[nodeId] ?? 0) + count;
  }

  bool shouldFailAdvertising(String nodeId, double rate) {
    if (_take(_advertisingFailures, nodeId)) return true;
    return rate > 0 && _random.nextDouble() < rate;
  }

  bool shouldFailConnect(String nodeId, double rate) {
    if (_take(_connectFailures, nodeId)) return true;
    return rate > 0 && _random.nextDouble() < rate;
  }

  bool shouldFailSubscribe(String nodeId, double rate) {
    if (_take(_subscribeFailures, nodeId)) return true;
    return rate > 0 && _random.nextDouble() < rate;
  }

  bool shouldFailWrite(String nodeId, double rate) {
    if (_take(_writeFailures, nodeId)) return true;
    return rate > 0 && _random.nextDouble() < rate;
  }

  bool shouldFailMtu(String nodeId, double rate) {
    if (_take(_mtuFailures, nodeId)) return true;
    return rate > 0 && _random.nextDouble() < rate;
  }

  bool shouldMissScan(double rate) {
    return rate > 0 && _random.nextDouble() < rate;
  }

  bool shouldDuplicate() {
    if (duplicateEvery <= 0) return false;
    _duplicateCounter++;
    if (_duplicateCounter % duplicateEvery != 0) return false;
    duplicatedPackets++;
    return true;
  }

  bool shouldReorder() {
    if (reorderEvery <= 0) return false;
    _reorderCounter++;
    if (_reorderCounter % reorderEvery != 0) return false;
    reorderedPackets++;
    return true;
  }

  bool shouldCorrupt() {
    if (corruptEvery <= 0) return false;
    _corruptCounter++;
    if (_corruptCounter % corruptEvery != 0) return false;
    corruptedPackets++;
    return true;
  }

  bool _take(Map<String, int> failures, String nodeId) {
    final remaining = failures[nodeId] ?? 0;
    if (remaining <= 0) return false;
    injectedFailures++;
    if (remaining == 1) {
      failures.remove(nodeId);
    } else {
      failures[nodeId] = remaining - 1;
    }
    return true;
  }

  void reset() {
    _advertisingFailures.clear();
    _connectFailures.clear();
    _subscribeFailures.clear();
    _writeFailures.clear();
    _mtuFailures.clear();
    forcedMtu = null;
    duplicateEvery = 0;
    reorderEvery = 0;
    corruptEvery = 0;
    _duplicateCounter = 0;
    _reorderCounter = 0;
    _corruptCounter = 0;
    duplicatedPackets = 0;
    reorderedPackets = 0;
    corruptedPackets = 0;
    injectedFailures = 0;
  }
}

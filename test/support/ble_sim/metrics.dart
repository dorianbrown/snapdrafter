/// Counters collected by the in-memory BLE network.
///
/// The point is to make a failure explain itself: how many connects were
/// refused, how deep the radio queues got, how often links retransmitted, and
/// how much was dropped before the cluster converged.
class BleSimMetrics {
  int scanResults = 0;
  int connectAttempts = 0;
  int connectFailures = 0;
  int disconnects = 0;
  int notificationsDelivered = 0;
  int writesDelivered = 0;
  int droppedNotifications = 0;
  int droppedWrites = 0;
  int advertisingFailures = 0;
  int scanMisses = 0;
  int maxQueueDepth = 0;
  int retransmits = 0;

  final Map<String, int> retransmitsByDevice = {};

  void recordRetry(String deviceId) {
    retransmits++;
    retransmitsByDevice[deviceId] = (retransmitsByDevice[deviceId] ?? 0) + 1;
  }

  void recordQueueDepth(int depth) {
    if (depth > maxQueueDepth) maxQueueDepth = depth;
  }

  Map<String, Object> toJson() => {
    'scanResults': scanResults,
    'connectAttempts': connectAttempts,
    'connectFailures': connectFailures,
    'disconnects': disconnects,
    'notificationsDelivered': notificationsDelivered,
    'writesDelivered': writesDelivered,
    'droppedNotifications': droppedNotifications,
    'droppedWrites': droppedWrites,
    'advertisingFailures': advertisingFailures,
    'scanMisses': scanMisses,
    'maxQueueDepth': maxQueueDepth,
    'retransmits': retransmits,
    'retransmitsByDevice': Map<String, int>.from(retransmitsByDevice),
  };

  String summary() {
    final retries = retransmitsByDevice.entries
        .map((e) => '${e.key}:$e.value')
        .join(',');
    return 'connects=$connectAttempts/${connectFailures} failed, '
        'disconnects=$disconnects, '
        'notify=$notificationsDelivered/$droppedNotifications dropped, '
        'writes=$writesDelivered/$droppedWrites dropped, '
        'retransmits=$retransmits${retries.isEmpty ? '' : ' ($retries)'}, '
        'advFailures=$advertisingFailures, '
        'maxQueue=$maxQueueDepth';
  }

  void reset() {
    scanResults = 0;
    connectAttempts = 0;
    connectFailures = 0;
    disconnects = 0;
    notificationsDelivered = 0;
    writesDelivered = 0;
    droppedNotifications = 0;
    droppedWrites = 0;
    advertisingFailures = 0;
    scanMisses = 0;
    maxQueueDepth = 0;
    retransmits = 0;
    retransmitsByDevice.clear();
  }
}

/// Link and radio characteristics for the in-memory BLE simulator.
///
/// [BleSimProfile.ideal] keeps the original, effectively instantaneous fake
/// network so existing tests stay fast and deterministic. The platform
/// profiles model enough of Android/iOS to expose the timing and connection
/// limits that only show up when eight real devices are in the same room.
class BleSimProfile {
  const BleSimProfile({
    required this.name,
    required this.useRadioScheduler,
    required this.mtu,
    required this.maxCentralConnections,
    required this.maxPeripheralConnections,
    required this.connectionInterval,
    required this.packetsPerInterval,
    required this.maxQueueDepth,
    required this.connectDelay,
    required this.discoverServicesDelay,
    required this.requestMtuDelay,
    required this.subscribeDelay,
    required this.advertisingStartDelay,
    required this.advertisingInterval,
    required this.scanInterval,
    required this.scanMissRate,
    required this.connectFailureRate,
    required this.subscribeFailureRate,
    required this.mtuFailureRate,
    required this.writeFailureRate,
    required this.advertisingFailureRate,
    required this.maxAdvertisingDataLength,
    required this.connectionStateOnConnect,
    required this.tickInterval,
    required this.linkAckTimeout,
    required this.linkChunkPacing,
    required this.reconnectDelaysSeconds,
  });

  final String name;

  /// When false, notifications are delivered immediately (plus [latency]) and
  /// the radio scheduler is bypassed. This preserves the original fake.
  final bool useRadioScheduler;

  final int mtu;
  final int maxCentralConnections;
  final int maxPeripheralConnections;

  /// Radio slot period. One packet per interval is sent across all links of a
  /// node, so more links means less throughput per link.
  final Duration connectionInterval;
  final int packetsPerInterval;

  /// Maximum queued radio jobs before the platform drops a notification.
  final int maxQueueDepth;

  final Duration connectDelay;
  final Duration discoverServicesDelay;
  final Duration requestMtuDelay;
  final Duration subscribeDelay;
  final Duration advertisingStartDelay;
  final Duration advertisingInterval;
  final Duration scanInterval;

  final double scanMissRate;
  final double connectFailureRate;
  final double subscribeFailureRate;
  final double mtuFailureRate;
  final double writeFailureRate;
  final double advertisingFailureRate;

  /// Legacy advertising data budget (flags + name + manufacturer data).
  final int maxAdvertisingDataLength;

  /// Android reports a connection event; iOS only reveals the link when a
  /// characteristic is subscribed. Hosts must not depend on connect events.
  final bool connectionStateOnConnect;

  /// Timings handed to [DraftBleLeader] so simulated time is cheap.
  final Duration tickInterval;
  final Duration linkAckTimeout;
  final Duration linkChunkPacing;

  /// Fast reconnect backoff for tests (the app uses 2/5/10/... seconds).
  final List<int> reconnectDelaysSeconds;

  bool get isIdeal => !useRadioScheduler;

  BleSimProfile copyWith({
    String? name,
    bool? useRadioScheduler,
    int? mtu,
    int? maxCentralConnections,
    int? maxPeripheralConnections,
    Duration? connectionInterval,
    int? packetsPerInterval,
    int? maxQueueDepth,
    Duration? connectDelay,
    Duration? discoverServicesDelay,
    Duration? requestMtuDelay,
    Duration? subscribeDelay,
    Duration? advertisingStartDelay,
    Duration? advertisingInterval,
    Duration? scanInterval,
    double? scanMissRate,
    double? connectFailureRate,
    double? subscribeFailureRate,
    double? mtuFailureRate,
    double? writeFailureRate,
    double? advertisingFailureRate,
    int? maxAdvertisingDataLength,
    bool? connectionStateOnConnect,
    Duration? tickInterval,
    Duration? linkAckTimeout,
    Duration? linkChunkPacing,
    List<int>? reconnectDelaysSeconds,
  }) {
    return BleSimProfile(
      name: name ?? this.name,
      useRadioScheduler: useRadioScheduler ?? this.useRadioScheduler,
      mtu: mtu ?? this.mtu,
      maxCentralConnections:
          maxCentralConnections ?? this.maxCentralConnections,
      maxPeripheralConnections:
          maxPeripheralConnections ?? this.maxPeripheralConnections,
      connectionInterval: connectionInterval ?? this.connectionInterval,
      packetsPerInterval: packetsPerInterval ?? this.packetsPerInterval,
      maxQueueDepth: maxQueueDepth ?? this.maxQueueDepth,
      connectDelay: connectDelay ?? this.connectDelay,
      discoverServicesDelay:
          discoverServicesDelay ?? this.discoverServicesDelay,
      requestMtuDelay: requestMtuDelay ?? this.requestMtuDelay,
      subscribeDelay: subscribeDelay ?? this.subscribeDelay,
      advertisingStartDelay:
          advertisingStartDelay ?? this.advertisingStartDelay,
      advertisingInterval: advertisingInterval ?? this.advertisingInterval,
      scanInterval: scanInterval ?? this.scanInterval,
      scanMissRate: scanMissRate ?? this.scanMissRate,
      connectFailureRate: connectFailureRate ?? this.connectFailureRate,
      subscribeFailureRate: subscribeFailureRate ?? this.subscribeFailureRate,
      mtuFailureRate: mtuFailureRate ?? this.mtuFailureRate,
      writeFailureRate: writeFailureRate ?? this.writeFailureRate,
      advertisingFailureRate:
          advertisingFailureRate ?? this.advertisingFailureRate,
      maxAdvertisingDataLength:
          maxAdvertisingDataLength ?? this.maxAdvertisingDataLength,
      connectionStateOnConnect:
          connectionStateOnConnect ?? this.connectionStateOnConnect,
      tickInterval: tickInterval ?? this.tickInterval,
      linkAckTimeout: linkAckTimeout ?? this.linkAckTimeout,
      linkChunkPacing: linkChunkPacing ?? this.linkChunkPacing,
      reconnectDelaysSeconds:
          reconnectDelaysSeconds ?? this.reconnectDelaysSeconds,
    );
  }

  /// Original behavior: instant connect/scan and immediate delivery.
  static const ideal = BleSimProfile(
    name: 'ideal',
    useRadioScheduler: false,
    mtu: 185,
    maxCentralConnections: 8,
    maxPeripheralConnections: 8,
    connectionInterval: Duration(milliseconds: 1),
    packetsPerInterval: 1000,
    maxQueueDepth: 100000,
    connectDelay: Duration.zero,
    discoverServicesDelay: Duration.zero,
    requestMtuDelay: Duration.zero,
    subscribeDelay: Duration.zero,
    advertisingStartDelay: Duration.zero,
    advertisingInterval: Duration(milliseconds: 100),
    scanInterval: Duration(milliseconds: 100),
    scanMissRate: 0,
    connectFailureRate: 0,
    subscribeFailureRate: 0,
    mtuFailureRate: 0,
    writeFailureRate: 0,
    advertisingFailureRate: 0,
    maxAdvertisingDataLength: 31,
    connectionStateOnConnect: true,
    tickInterval: Duration(seconds: 2),
    linkAckTimeout: Duration(milliseconds: 1200),
    linkChunkPacing: Duration(milliseconds: 30),
    reconnectDelaysSeconds: [1, 1, 1, 1, 1, 1, 1, 1],
  );

  /// Contemporary Android phone: 517 MTU, 15 ms connection interval, up to
  /// seven simultaneous links in each role.
  static const android = BleSimProfile(
    name: 'android',
    useRadioScheduler: true,
    mtu: 517,
    maxCentralConnections: 7,
    maxPeripheralConnections: 7,
    connectionInterval: Duration(milliseconds: 15),
    packetsPerInterval: 1,
    maxQueueDepth: 128,
    connectDelay: Duration(milliseconds: 200),
    discoverServicesDelay: Duration(milliseconds: 250),
    requestMtuDelay: Duration(milliseconds: 80),
    subscribeDelay: Duration(milliseconds: 80),
    advertisingStartDelay: Duration(milliseconds: 300),
    advertisingInterval: Duration(milliseconds: 100),
    scanInterval: Duration(milliseconds: 100),
    scanMissRate: 0,
    connectFailureRate: 0,
    subscribeFailureRate: 0,
    mtuFailureRate: 0,
    writeFailureRate: 0,
    advertisingFailureRate: 0,
    maxAdvertisingDataLength: 31,
    connectionStateOnConnect: true,
    tickInterval: Duration(seconds: 2),
    linkAckTimeout: Duration(milliseconds: 1200),
    linkChunkPacing: Duration(milliseconds: 30),
    reconnectDelaysSeconds: [1, 1, 1, 1, 1, 1, 1, 1],
  );

  /// iPhone: 185 MTU, 30 ms connection interval, and no connection event
  /// until a characteristic is subscribed.
  static const ios = BleSimProfile(
    name: 'ios',
    useRadioScheduler: true,
    mtu: 185,
    maxCentralConnections: 7,
    maxPeripheralConnections: 7,
    connectionInterval: Duration(milliseconds: 30),
    packetsPerInterval: 1,
    maxQueueDepth: 128,
    connectDelay: Duration(milliseconds: 300),
    discoverServicesDelay: Duration(milliseconds: 400),
    requestMtuDelay: Duration(milliseconds: 120),
    subscribeDelay: Duration(milliseconds: 120),
    advertisingStartDelay: Duration(milliseconds: 400),
    advertisingInterval: Duration(milliseconds: 100),
    scanInterval: Duration(milliseconds: 100),
    scanMissRate: 0,
    connectFailureRate: 0,
    subscribeFailureRate: 0,
    mtuFailureRate: 0,
    writeFailureRate: 0,
    advertisingFailureRate: 0,
    maxAdvertisingDataLength: 31,
    connectionStateOnConnect: false,
    tickInterval: Duration(seconds: 2),
    linkAckTimeout: Duration(milliseconds: 1200),
    linkChunkPacing: Duration(milliseconds: 30),
    reconnectDelaysSeconds: [1, 1, 1, 1, 1, 1, 1, 1],
  );

  /// A low-end phone with a tight link budget, used to force relay topology.
  static BleSimProfile get androidLowEnd => android.copyWith(
    name: 'android-low-end',
    maxPeripheralConnections: 4,
    maxCentralConnections: 4,
    maxQueueDepth: 48,
    connectionInterval: Duration(milliseconds: 30),
  );

  @override
  String toString() => 'BleSimProfile($name)';
}

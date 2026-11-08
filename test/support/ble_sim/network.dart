import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:snapdrafter/services/draft/ble_platform.dart';
import 'package:snapdrafter/services/draft/draft_ble_service.dart';
import 'package:universal_ble/universal_ble.dart';

import 'faults.dart';
import 'metrics.dart';
import 'profile.dart';

/// In-memory BLE network simulator for multi-node draft tests.
///
/// Models the parts of real BLE that break large drafts:
///   - a per-node radio shared by every link in both roles,
///   - per-profile central and peripheral connection limits,
///   - a negotiated MTU per link,
///   - a bounded per-node radio queue (overflow drops silently, like the
///     platform notification buffers),
///   - configurable random or deterministic packet loss,
///   - link latency, connect/MTU/discovery delays, and scan/advertising timing,
///   - disconnect and advertising-failure injection.
///
/// Each [FakeBleNode] exposes both a [BleCentral] and a [BlePeripheral] so a
/// single node can act as a relay (central uplink + peripheral downlink).
class FakeBleNetwork {
  FakeBleNetwork({
    int? mtu,
    this.maxConnectionsPerNode = 8,
    this.dropRate = 0.0,
    this.queueDepth = 20,
    this.latency = const Duration(milliseconds: 1),
    int? seed,
    BleSimProfile? profile,
  }) : profile = profile ?? BleSimProfile.ideal,
       mtu = mtu ?? profile?.mtu ?? 185,
       _random = Random(seed) {
    metrics = BleSimMetrics();
    faults = BleSimFaults(seed: seed);
  }

  final Map<String, FakeBleNode> nodes = {};
  final BleSimProfile profile;
  late final BleSimMetrics metrics;
  late final BleSimFaults faults;

  int mtu;
  int maxConnectionsPerNode;
  double dropRate;
  int queueDepth;
  Duration latency;
  final Random _random;

  /// Optional deterministic override. Receives a monotonically increasing
  /// packet index and returns true to drop the packet.
  bool Function(int packetIndex)? dropPolicy;

  int _packetCounter = 0;
  int get droppedPackets => _droppedPackets;
  int _droppedPackets = 0;

  FakeBleNode addNode(String deviceId, {String? name}) {
    final node = FakeBleNode._(this, deviceId, name ?? deviceId);
    nodes[deviceId] = node;
    return node;
  }

  /// Schedules a fault at the current (real or fake) time plus [delay].
  Timer scheduleFault(Duration delay, void Function() action) =>
      Timer(delay, action);

  /// Turns a node's radio off/on. A paused node stops scanning, advertising
  /// and delivering queued traffic until enabled again.
  void setRadioEnabled(String deviceId, bool enabled) {
    final node = nodes[deviceId];
    if (node == null) return;
    node.radioEnabled = enabled;
    if (!enabled) {
      node._dropQueuedRadioJobs();
    }
  }

  bool _shouldDrop() {
    final policy = dropPolicy;
    if (policy != null) return policy(_packetCounter++);
    if (dropRate <= 0) return false;
    _packetCounter++;
    return _random.nextDouble() < dropRate;
  }

  void _recordDrop() => _droppedPackets++;

  void dispose() {
    for (final node in nodes.values) {
      node.dispose();
    }
  }
}

class FakeBleNode {
  FakeBleNode._(this.network, this.deviceId, this.localName)
    : central = FakeNetworkCentral._(null),
      peripheral = FakeNetworkPeripheral._(null) {
    central._node = this;
    peripheral._node = this;
    if (network.profile.useRadioScheduler) {
      _radioTimer = Timer.periodic(
        network.profile.connectionInterval,
        _drainRadio,
      );
    }
  }

  final FakeBleNetwork network;
  final String deviceId;
  String localName;

  final FakeNetworkCentral central;
  final FakeNetworkPeripheral peripheral;

  /// Outgoing links where this node is the central, keyed by remote device id.
  final Map<String, FakeBleLink> links = {};

  /// Incoming links where this node is the peripheral, keyed by central id.
  final Map<String, FakeBleLink> incomingLinks = {};

  /// One radio serves both roles on this node. A relay therefore shares its
  /// uplink and downlink airtime instead of getting two free radios.
  final Queue<_RadioJob> _radioQueue = Queue<_RadioJob>();

  /// Optional test-only cap for the peripheral role. Useful for deterministic
  /// deep-relay topologies where the app's configured limit is lower than the
  /// platform limit.
  int? maxPeripheralConnectionsOverride;

  Timer? _radioTimer;
  bool radioEnabled = true;

  bool get isAdvertising => peripheral._advertising;

  int get totalLinkCount => links.length + incomingLinks.length;

  void _enqueueRadio(_RadioJob job) {
    if (!radioEnabled) {
      job.drop();
      return;
    }
    if (_radioQueue.length >= network.profile.maxQueueDepth) {
      job.drop();
      return;
    }

    if (network.faults.shouldDuplicate()) {
      _radioQueue.add(job.copy());
    }
    if (network.faults.shouldCorrupt() && job.bytes.isNotEmpty) {
      job.corrupt();
    }
    if (network.faults.shouldReorder() && _radioQueue.isNotEmpty) {
      final last = _radioQueue.removeLast();
      _radioQueue.add(job);
      _radioQueue.add(last);
    } else {
      _radioQueue.add(job);
    }
    network.metrics.recordQueueDepth(_radioQueue.length);
  }

  void _drainRadio(Timer _) {
    if (!radioEnabled) return;
    final limit = network.profile.packetsPerInterval;
    var delivered = 0;
    var inspected = 0;
    while (_radioQueue.isNotEmpty &&
        delivered < limit &&
        inspected < limit + 8) {
      final job = _radioQueue.removeFirst();
      inspected++;
      if (!job.link.connected) {
        job.cancel();
        continue;
      }
      if (network._shouldDrop()) {
        job.drop();
        delivered++;
        continue;
      }
      if (!job.isNotification &&
          network.faults.shouldFailWrite(
            deviceId,
            network.profile.writeFailureRate,
          )) {
        job.drop();
        delivered++;
        continue;
      }
      job.deliver();
      delivered++;
    }
  }

  void _dropQueuedRadioJobs() {
    while (_radioQueue.isNotEmpty) {
      _radioQueue.removeFirst().drop();
    }
  }

  void dispose() {
    _radioTimer?.cancel();
    _radioTimer = null;
    _dropQueuedRadioJobs();
    central.dispose();
    peripheral.dispose();
  }
}

class FakeBleLink {
  FakeBleLink({
    required this.central,
    required this.peripheral,
    required this.mtu,
  });

  final FakeBleNode central;
  final FakeBleNode peripheral;
  int mtu;
  final Set<String> subscribedChars = {};
  int pendingDeliveries = 0;
  bool connected = true;
}

// ---------------------------------------------------------------------------
// Radio jobs
// ---------------------------------------------------------------------------

class _RadioJob {
  _RadioJob.notification({
    required this.link,
    required this.characteristicId,
    required this.bytes,
  }) : isNotification = true,
       completer = null;

  _RadioJob.write({
    required this.link,
    required this.characteristicId,
    required this.bytes,
  }) : isNotification = false,
       completer = Completer<void>();

  final FakeBleLink link;
  final bool isNotification;
  final String characteristicId;
  Uint8List bytes;
  final Completer<void>? completer;

  _RadioJob copy() {
    if (isNotification) {
      return _RadioJob.notification(
        link: link,
        characteristicId: characteristicId,
        bytes: Uint8List.fromList(bytes),
      );
    }
    return _RadioJob.write(
      link: link,
      characteristicId: characteristicId,
      bytes: Uint8List.fromList(bytes),
    );
  }

  void deliver() {
    if (!link.connected) {
      cancel();
      return;
    }
    if (!link.central.radioEnabled || !link.peripheral.radioEnabled) {
      drop();
      return;
    }
    if (isNotification) {
      if (!link.subscribedChars.contains(characteristicId)) {
        cancel();
        return;
      }
      link.central.central._deliverNotificationNow(
        link,
        characteristicId,
        bytes,
      );
      return;
    }

    final handler = link.peripheral.peripheral._writeHandler;
    try {
      if (handler != null) {
        handler(link.central.deviceId, characteristicId, 0, bytes);
      }
      link.central.network.metrics.writesDelivered++;
      completer?.complete();
    } catch (error, stackTrace) {
      completer?.completeError(error, stackTrace);
    }
  }

  void drop() {
    final network = link.central.network;
    network._recordDrop();
    if (isNotification) {
      network.metrics.droppedNotifications++;
      return;
    }
    network.metrics.droppedWrites++;
    // A dropped write is indistinguishable from a successful platform write
    // on some stacks; complete so fire-and-forget callers do not leak errors.
    completer?.complete();
  }

  void cancel() {
    if (isNotification) return;
    if (completer != null && !completer!.isCompleted) {
      completer!.complete();
    }
  }

  void corrupt() {
    final index = bytes.length ~/ 2;
    bytes[index] ^= 0xFF;
  }
}

// ---------------------------------------------------------------------------
// Central
// ---------------------------------------------------------------------------

class FakeNetworkCentral implements BleCentral {
  FakeNetworkCentral._(this._node);

  FakeBleNode? _node;
  FakeBleNode get node => _node!;

  final _scanCtrl = StreamController<BleDevice>.broadcast();
  final _connectionCtrls = <String, StreamController<bool>>{};
  final _charValueCtrls = <String, StreamController<Uint8List>>{};

  bool _scanning = false;
  Timer? _scanTimer;
  bool _disposed = false;

  @override
  Stream<BleDevice> get scanStream => _scanCtrl.stream;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    if (_disposed) return;
    _scanning = true;
    if (node.network.profile.useRadioScheduler) {
      _scanTimer?.cancel();
      _scanTimer = Timer.periodic(
        node.network.profile.scanInterval,
        (_) => _emitVisibleAdvertisers(),
      );
    } else {
      // Original behavior: devices already advertising are visible at once.
      _emitVisibleAdvertisers();
    }
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  void _emitVisibleAdvertisers() {
    if (!_scanning || !node.radioEnabled) return;
    for (final other in node.network.nodes.values) {
      if (other.deviceId == node.deviceId) continue;
      if (!other.peripheral._advertising || !other.radioEnabled) continue;
      if (node.network.profile.scanMissRate > 0 &&
          node.network.faults.shouldMissScan(
            node.network.profile.scanMissRate,
          )) {
        node.network.metrics.scanMisses++;
        continue;
      }
      _emitScan(other);
    }
  }

  void _emitScan(FakeBleNode other) {
    if (!_scanning || _disposed) return;
    final manufacturer = other.peripheral._advertisedManufacturerData;
    node.network.metrics.scanResults++;
    _scanCtrl.add(
      BleDevice(
        deviceId: other.deviceId,
        name: other.peripheral._advertisedName ?? other.localName,
        rssi: -40 - (other.deviceId.hashCode % 40),
        manufacturerDataList: manufacturer != null ? [manufacturer] : const [],
      ),
    );
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_disposed) throw Exception('Central disposed');
    node.network.metrics.connectAttempts++;

    if (!node.radioEnabled) {
      node.network.metrics.connectFailures++;
      throw Exception('Bluetooth is off on ${node.deviceId}');
    }

    final profile = node.network.profile;
    if (profile.useRadioScheduler) {
      await Future<void>.delayed(profile.connectDelay);
    }

    final remote = node.network.nodes[deviceId];
    if (remote == null) {
      node.network.metrics.connectFailures++;
      throw Exception('Device not found: $deviceId');
    }
    if (!remote.peripheral._advertising || !remote.radioEnabled) {
      node.network.metrics.connectFailures++;
      throw Exception('Device is not advertising: $deviceId');
    }
    if (node.network.faults.shouldFailConnect(
      node.deviceId,
      profile.connectFailureRate,
    )) {
      node.network.metrics.connectFailures++;
      throw Exception('Connection failed: $deviceId');
    }

    final maxCentral = profile.useRadioScheduler
        ? profile.maxCentralConnections
        : node.network.maxConnectionsPerNode;
    final maxPeripheral =
        remote.maxPeripheralConnectionsOverride ??
        (profile.useRadioScheduler
            ? profile.maxPeripheralConnections
            : node.network.maxConnectionsPerNode);

    if (node.links.length >= maxCentral) {
      node.network.metrics.connectFailures++;
      throw Exception('Central connection limit reached on ${node.deviceId}');
    }
    if (remote.incomingLinks.length >= maxPeripheral) {
      node.network.metrics.connectFailures++;
      throw Exception('Connection limit reached on $deviceId');
    }
    if (node.links.containsKey(deviceId)) return;

    final link = FakeBleLink(
      central: node,
      peripheral: remote,
      mtu: min(node.network.mtu, profile.mtu),
    );
    node.links[deviceId] = link;
    remote.incomingLinks[node.deviceId] = link;

    if (profile.connectionStateOnConnect) {
      remote.peripheral._connectionCtrl.add(
        BlePeripheralConnectionStateChanged(node.deviceId, true),
      );
    }
    _connectionCtrls
        .putIfAbsent(deviceId, () => StreamController<bool>.broadcast())
        .add(true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    if (_disposed) return;
    final link = node.links.remove(deviceId);
    if (link == null) return;
    link.connected = false;
    link.peripheral.incomingLinks.remove(node.deviceId);
    link.peripheral.peripheral._connectionCtrl.add(
      BlePeripheralConnectionStateChanged(node.deviceId, false),
    );
    for (final char in link.subscribedChars) {
      link.peripheral.peripheral._charSubCtrl.add(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: node.deviceId,
          characteristicId: char,
          isSubscribed: false,
          name: null,
        ),
      );
    }
    link.subscribedChars.clear();
    _connectionCtrls[deviceId]?.add(false);
    node.network.metrics.disconnects++;
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    if (_disposed) throw Exception('Central disposed');
    final link = node.links[deviceId];
    if (link == null) throw Exception('Not connected to $deviceId');
    final profile = node.network.profile;
    if (profile.useRadioScheduler) {
      await Future<void>.delayed(profile.requestMtuDelay);
    }
    if (node.network.faults.shouldFailMtu(
      node.deviceId,
      profile.mtuFailureRate,
    )) {
      throw Exception('MTU request failed on $deviceId');
    }
    final forced = node.network.faults.forcedMtu;
    final effective = forced ?? min(mtu, min(node.network.mtu, profile.mtu));
    link.mtu = max(23, effective);
    link.peripheral.peripheral._mtuCtrl.add(
      BlePeripheralMtuChanged(node.deviceId, link.mtu),
    );
    return link.mtu;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    if (_disposed) throw Exception('Central disposed');
    final profile = node.network.profile;
    if (profile.useRadioScheduler) {
      await Future<void>.delayed(profile.discoverServicesDelay);
    }
    return [BleService(DraftBleService.serviceUuid, const [])];
  }

  @override
  Stream<bool> connectionStream(String deviceId) {
    return _connectionCtrls
        .putIfAbsent(deviceId, () => StreamController<bool>.broadcast())
        .stream;
  }

  @override
  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicUuid,
  ) {
    final key = '$deviceId/$characteristicUuid';
    return _charValueCtrls
        .putIfAbsent(key, () => StreamController<Uint8List>.broadcast())
        .stream;
  }

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    if (_disposed) return;
    final link = node.links[deviceId];
    if (link == null) throw Exception('Not connected to $deviceId');
    final profile = node.network.profile;
    if (profile.useRadioScheduler) {
      await Future<void>.delayed(profile.subscribeDelay);
    }
    if (node.network.faults.shouldFailSubscribe(
      node.deviceId,
      profile.subscribeFailureRate,
    )) {
      throw Exception('Subscribe failed on $deviceId');
    }
    link.subscribedChars.add(characteristicUuid);
    link.peripheral.peripheral._charSubCtrl.add(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: node.deviceId,
        characteristicId: characteristicUuid,
        isSubscribed: true,
        name: null,
      ),
    );
  }

  @override
  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    if (_disposed) return;
    final link = node.links[deviceId];
    if (link == null) return;
    link.subscribedChars.remove(characteristicUuid);
    link.peripheral.peripheral._charSubCtrl.add(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: node.deviceId,
        characteristicId: characteristicUuid,
        isSubscribed: false,
        name: null,
      ),
    );
  }

  @override
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    Uint8List value,
  ) async {
    if (_disposed) throw Exception('Central disposed');
    final link = node.links[deviceId];
    if (link == null) throw Exception('Not connected to $deviceId');

    final profile = node.network.profile;
    if (node.network.faults.shouldFailWrite(
      node.deviceId,
      profile.writeFailureRate,
    )) {
      node.network.metrics.droppedWrites++;
      throw Exception('Write failed on $deviceId');
    }

    if (profile.useRadioScheduler) {
      final job = _RadioJob.write(
        link: link,
        characteristicId: characteristicUuid,
        bytes: value,
      );
      node._enqueueRadio(job);
      // The enqueue path may drop immediately; in that case the job's future
      // is completed, so wait for it. Otherwise wait for delivery.
      await job.completer!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      return;
    }

    await Future<void>.delayed(node.network.latency);
    final handler = link.peripheral.peripheral._writeHandler;
    if (handler != null) {
      handler(node.deviceId, characteristicUuid, 0, value);
    }
    node.network.metrics.writesDelivered++;
  }

  /// Delivers a downstream notification to this central, modelling queue
  /// overflow and packet loss for the original (non-radio) fake.
  void _deliverNotification(
    FakeBleLink link,
    String charUuid,
    Uint8List value,
  ) {
    if (!link.connected) return;
    if (link.pendingDeliveries >= node.network.queueDepth) {
      node.network._recordDrop();
      node.network.metrics.droppedNotifications++;
      return;
    }
    if (node.network._shouldDrop()) {
      node.network._recordDrop();
      node.network.metrics.droppedNotifications++;
      return;
    }
    link.pendingDeliveries++;
    Future<void>.delayed(node.network.latency, () {
      link.pendingDeliveries--;
      _deliverNotificationNow(link, charUuid, value);
    });
  }

  void _deliverNotificationNow(
    FakeBleLink link,
    String charUuid,
    Uint8List value,
  ) {
    if (_disposed || !link.connected) return;
    final key = '${link.peripheral.deviceId}/$charUuid';
    _charValueCtrls[key]?.add(value);
    node.network.metrics.notificationsDelivered++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanCtrl.close();
    for (final c in _connectionCtrls.values) {
      c.close();
    }
    for (final c in _charValueCtrls.values) {
      c.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Peripheral
// ---------------------------------------------------------------------------

class FakeNetworkPeripheral implements BlePeripheral {
  FakeNetworkPeripheral._(this._node);

  FakeBleNode? _node;
  FakeBleNode get node => _node!;

  final _connectionCtrl =
      StreamController<BlePeripheralConnectionStateChanged>.broadcast();
  final _charSubCtrl =
      StreamController<
        BlePeripheralCharacteristicSubscriptionChanged
      >.broadcast();
  final _mtuCtrl = StreamController<BlePeripheralMtuChanged>.broadcast();
  final _advertisingStateCtrl =
      StreamController<BlePeripheralAdvertisingStateChanged>.broadcast();

  bool _advertising = false;
  String? _advertisedName;
  ManufacturerData? _advertisedManufacturerData;
  BlePeripheralService? service;
  bool _disposed = false;

  PeripheralReadRequestResult? Function(String, String, int, Uint8List?)?
  readHandler;
  PeripheralWriteRequestResult Function(String, String, int, Uint8List?)?
  _writeHandler;

  @override
  Stream<BlePeripheralConnectionStateChanged> get connectionStateStream =>
      _connectionCtrl.stream;

  @override
  Stream<BlePeripheralCharacteristicSubscriptionChanged>
  get characteristicSubscriptionStream => _charSubCtrl.stream;

  @override
  Stream<BlePeripheralMtuChanged> get mtuChangedStream => _mtuCtrl.stream;

  @override
  Stream<BlePeripheralAdvertisingStateChanged> get advertisingStateStream =>
      _advertisingStateCtrl.stream;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async {
    return BlePeripheralCapabilities(
      supportsPeripheralMode: true,
      supportsManufacturerDataInAdvertisement: true,
      supportsManufacturerDataInScanResponse:
          node.network.profile.useRadioScheduler,
      supportsServiceDataInAdvertisement: false,
      supportsServiceDataInScanResponse: false,
      supportsTargetedCharacteristicUpdate: true,
      supportsAdvertisingTimeout: false,
    );
  }

  @override
  Future<void> addService(BlePeripheralService service) async {
    this.service = service;
  }

  @override
  void setReadRequestHandlers(
    PeripheralReadRequestResult? Function(String, String, int, Uint8List?)?
    handler,
  ) {
    readHandler = handler;
  }

  @override
  void setWriteRequestHandlers(
    PeripheralWriteRequestResult Function(String, String, int, Uint8List?)?
    handler,
  ) {
    _writeHandler = handler;
  }

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    final profile = node.network.profile;
    if (!profile.useRadioScheduler) {
      _advertising = true;
      _advertisedName = localName;
      _advertisedManufacturerData = manufacturerData;
      // Notify every scanning node in the network.
      for (final other in node.network.nodes.values) {
        if (other.deviceId == node.deviceId) continue;
        other.central._emitScan(node);
      }
      return;
    }

    await Future<void>.delayed(profile.advertisingStartDelay);
    if (_disposed) return;
    if (!node.radioEnabled) {
      _emitAdvertisingError('Bluetooth is off');
      return;
    }
    if (node.network.faults.shouldFailAdvertising(
      node.deviceId,
      profile.advertisingFailureRate,
    )) {
      node.network.metrics.advertisingFailures++;
      _emitAdvertisingError('ADVERTISE_FAILED_INTERNAL_ERROR');
      return;
    }
    if (_advertising) {
      _emitAdvertisingError('ADVERTISE_FAILED_ALREADY_STARTED');
      return;
    }
    if (_advertisementSize(localName, manufacturerData) >
        profile.maxAdvertisingDataLength) {
      node.network.metrics.advertisingFailures++;
      _emitAdvertisingError('ADVERTISE_FAILED_DATA_TOO_LARGE');
      return;
    }

    _advertising = true;
    _advertisedName = localName;
    _advertisedManufacturerData = manufacturerData;
    // Scanning nodes sample advertisers on their own scan timer, so scan
    // windows and misses apply. Advertising does not push directly.
    _advertisingStateCtrl.add(
      BlePeripheralAdvertisingStateChanged(
        PeripheralAdvertisingState.advertising,
        null,
      ),
    );
  }

  int _advertisementSize(String? localName, ManufacturerData? manufacturer) {
    var size = 3; // flags
    if (localName != null) {
      size += 2 + utf8.encode(localName).length;
    }
    if (manufacturer != null) {
      size += 2 + 2 + manufacturer.payload.length;
    }
    return size;
  }

  void _emitAdvertisingError(String error) {
    if (_disposed) return;
    _advertisingStateCtrl.add(
      BlePeripheralAdvertisingStateChanged(
        PeripheralAdvertisingState.error,
        error,
      ),
    );
  }

  @override
  Future<void> stopAdvertising() async {
    if (_disposed) return;
    _advertising = false;
    _advertisingStateCtrl.add(
      BlePeripheralAdvertisingStateChanged(
        PeripheralAdvertisingState.idle,
        null,
      ),
    );
  }

  @override
  Future<void> clearServices() async {
    service = null;
  }

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async =>
      node.radioEnabled
      ? PeripheralReadinessState.ready
      : PeripheralReadinessState.bluetoothOff;

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {
    if (_disposed) return;
    final targets = <FakeBleLink>[];
    if (deviceId != null) {
      final link = node.incomingLinks[deviceId];
      if (link != null) targets.add(link);
    } else {
      targets.addAll(node.incomingLinks.values);
    }
    for (final link in targets) {
      if (!link.subscribedChars.contains(characteristicId)) continue;
      if (node.network.profile.useRadioScheduler) {
        node._enqueueRadio(
          _RadioJob.notification(
            link: link,
            characteristicId: characteristicId,
            bytes: value,
          ),
        );
      } else {
        link.central.central._deliverNotification(
          link,
          characteristicId,
          value,
        );
      }
    }
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async {
    final link = node.incomingLinks[deviceId];
    if (link == null) return null;
    return link.mtu - 3;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionCtrl.close();
    _charSubCtrl.close();
    _mtuCtrl.close();
    _advertisingStateCtrl.close();
  }
}

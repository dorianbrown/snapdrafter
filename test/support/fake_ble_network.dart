import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'package:snapdrafter/services/draft/ble_platform.dart';

/// In-memory BLE network simulator for multi-node draft tests.
///
/// Models the parts of real BLE that break large drafts:
///   - a per-node connection limit (`maxConnectionsPerNode`),
///   - a negotiated MTU per link,
///   - a bounded per-link delivery queue (overflow drops silently, like the
///     platform notification buffers),
///   - configurable random or deterministic packet loss,
///   - link latency and disconnect injection.
///
/// Each [FakeBleNode] exposes both a [BleCentral] and a [BlePeripheral] so a
/// single node can act as a relay (central uplink + peripheral downlink).
class FakeBleNetwork {
  FakeBleNetwork({
    this.mtu = 185,
    this.maxConnectionsPerNode = 8,
    this.dropRate = 0.0,
    this.queueDepth = 20,
    this.latency = const Duration(milliseconds: 1),
    int? seed,
  }) : _random = Random(seed);

  final Map<String, FakeBleNode> nodes = {};

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

  bool _shouldDrop() {
    final policy = dropPolicy;
    if (policy != null) return policy(_packetCounter++);
    if (dropRate <= 0) return false;
    _packetCounter++;
    return _random.nextDouble() < dropRate;
  }

  void _recordDrop() => _droppedPackets++;
}

class FakeBleNode {
  FakeBleNode._(this.network, this.deviceId, this.localName)
    : central = FakeNetworkCentral._(null),
      peripheral = FakeNetworkPeripheral._(null) {
    central._node = this;
    peripheral._node = this;
  }

  final FakeBleNetwork network;
  final String deviceId;
  String localName;

  final FakeNetworkCentral central;
  final FakeNetworkPeripheral peripheral;

  /// Outgoing links where this node is the central, keyed by remote device id.
  final Map<String, _Link> links = {};

  /// Incoming links where this node is the peripheral, keyed by central id.
  final Map<String, _Link> incomingLinks = {};

  bool get isAdvertising => peripheral._advertising;

  int get totalLinkCount => links.length + incomingLinks.length;
}

class _Link {
  _Link({required this.central, required this.peripheral, required this.mtu});

  final FakeBleNode central;
  final FakeBleNode peripheral;
  int mtu;
  final Set<String> subscribedChars = {};
  int pendingDeliveries = 0;
  bool connected = true;
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
  final _scanSubs = <String, List<StreamSubscription<BleDevice>>>{};

  bool _scanning = false;

  @override
  Stream<BleDevice> get scanStream => _scanCtrl.stream;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    _scanning = true;
    // Emit nodes that are already advertising.
    for (final other in node.network.nodes.values) {
      if (other.deviceId == node.deviceId) continue;
      if (other.peripheral._advertising) {
        _emitScan(other);
      }
    }
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
  }

  void _emitScan(FakeBleNode other) {
    if (!_scanning) return;
    final manufacturer = other.peripheral._advertisedManufacturerData;
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
    final remote = node.network.nodes[deviceId];
    if (remote == null) {
      throw Exception('Device not found: $deviceId');
    }
    if (!remote.peripheral._advertising) {
      throw Exception('Device is not advertising: $deviceId');
    }
    if (remote.incomingLinks.length >= node.network.maxConnectionsPerNode) {
      throw Exception('Connection limit reached on $deviceId');
    }
    if (node.links.containsKey(deviceId)) return;

    final link = _Link(
      central: node,
      peripheral: remote,
      mtu: node.network.mtu,
    );
    node.links[deviceId] = link;
    remote.incomingLinks[node.deviceId] = link;

    remote.peripheral._connectionCtrl.add(
      BlePeripheralConnectionStateChanged(node.deviceId, true),
    );
    _connectionCtrls
        .putIfAbsent(deviceId, () => StreamController<bool>.broadcast())
        .add(true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
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
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    final link = node.links[deviceId];
    if (link == null) throw Exception('Not connected to $deviceId');
    link.mtu = min(mtu, node.network.mtu);
    link.peripheral.peripheral._mtuCtrl.add(
      BlePeripheralMtuChanged(node.deviceId, link.mtu),
    );
    return link.mtu;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    return [BleService('4a2e1d0a-0000-4000-8000-00805f9b34fb', [])];
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
    final link = node.links[deviceId];
    if (link == null) throw Exception('Not connected to $deviceId');
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
    final link = node.links[deviceId];
    if (link == null) throw Exception('Not connected to $deviceId');
    await Future<void>.delayed(node.network.latency);
    final handler = link.peripheral.peripheral._writeHandler;
    if (handler != null) {
      handler(node.deviceId, characteristicUuid, 0, value);
    }
  }

  /// Delivers a downstream notification to this central, modelling queue
  /// overflow and packet loss.
  void _deliverNotification(_Link link, String charUuid, Uint8List value) {
    if (!link.connected) return;
    if (link.pendingDeliveries >= node.network.queueDepth) {
      node.network._recordDrop();
      return;
    }
    if (node.network._shouldDrop()) {
      node.network._recordDrop();
      return;
    }
    link.pendingDeliveries++;
    Future<void>.delayed(node.network.latency, () {
      link.pendingDeliveries--;
      final key = '${link.peripheral.deviceId}/$charUuid';
      _charValueCtrls[key]?.add(value);
    });
  }

  void _emitScanResult(FakeBleNode advertisingNode) {
    _emitScan(advertisingNode);
  }

  void dispose() {
    _scanCtrl.close();
    for (final c in _connectionCtrls.values) {
      c.close();
    }
    for (final c in _charValueCtrls.values) {
      c.close();
    }
    for (final subs in _scanSubs.values) {
      for (final s in subs) {
        s.cancel();
      }
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
    return const BlePeripheralCapabilities(
      supportsPeripheralMode: true,
      supportsManufacturerDataInAdvertisement: false,
      supportsManufacturerDataInScanResponse: false,
      supportsServiceDataInAdvertisement: false,
      supportsServiceDataInScanResponse: false,
      supportsTargetedCharacteristicUpdate: true,
      supportsAdvertisingTimeout: false,
    );
  }

  @override
  Future<void> addService(BlePeripheralService service) async {
    service = service;
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
    _advertising = true;
    _advertisedName = localName;
    _advertisedManufacturerData = manufacturerData;
    // Notify every scanning node in the network.
    for (final other in node.network.nodes.values) {
      if (other.deviceId == node.deviceId) continue;
      other.central._emitScanResult(node);
    }
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
  }

  @override
  Future<void> clearServices() async {
    service = null;
  }

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async =>
      PeripheralReadinessState.ready;

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {
    final targets = <_Link>[];
    if (deviceId != null) {
      final link = node.incomingLinks[deviceId];
      if (link != null) targets.add(link);
    } else {
      targets.addAll(node.incomingLinks.values);
    }
    for (final link in targets) {
      if (!link.subscribedChars.contains(characteristicId)) continue;
      link.central.central._deliverNotification(link, characteristicId, value);
    }
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async {
    final link = node.incomingLinks[deviceId];
    if (link == null) return null;
    return link.mtu - 3;
  }

  void dispose() {
    _connectionCtrl.close();
    _charSubCtrl.close();
    _mtuCtrl.close();
    _advertisingStateCtrl.close();
  }
}

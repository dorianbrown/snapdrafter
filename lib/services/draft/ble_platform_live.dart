import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import 'ble_platform.dart';

/// Production [BleCentral] implementation that delegates directly to
/// [UniversalBle].
class LiveBleCentral implements BleCentral {
  @override
  Stream<BleDevice> get scanStream => UniversalBle.scanStream;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) {
    return UniversalBle.startScan(
      scanFilter: scanFilter,
      platformConfig: platformConfig,
    );
  }

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) => UniversalBle.connect(deviceId);

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Future<int> requestMtu(String deviceId, int mtu) =>
      UniversalBle.requestMtu(deviceId, mtu);

  @override
  Future<List<BleService>> discoverServices(String deviceId) =>
      UniversalBle.discoverServices(deviceId);

  @override
  Stream<bool> connectionStream(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicUuid,
  ) => UniversalBle.characteristicValueStream(deviceId, characteristicUuid);

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    return UniversalBle.subscribeNotifications(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
  }

  @override
  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    return UniversalBle.unsubscribe(deviceId, serviceUuid, characteristicUuid);
  }

  @override
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    Uint8List value,
  ) {
    return UniversalBle.write(deviceId, serviceUuid, characteristicUuid, value);
  }
}

/// Production [BlePeripheral] implementation that delegates directly to
/// [UniversalBlePeripheral].
class LiveBlePeripheral implements BlePeripheral {
  @override
  Stream<BlePeripheralConnectionStateChanged> get connectionStateStream =>
      UniversalBlePeripheral.connectionStateStream;

  @override
  Stream<BlePeripheralCharacteristicSubscriptionChanged>
  get characteristicSubscriptionStream =>
      UniversalBlePeripheral.characteristicSubscriptionStream;

  @override
  Stream<BlePeripheralMtuChanged> get mtuChangedStream =>
      UniversalBlePeripheral.mtuChangedStream;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() {
    return UniversalBlePeripheral.getCapabilities();
  }

  @override
  Future<void> addService(BlePeripheralService service) {
    return UniversalBlePeripheral.addService(service);
  }

  @override
  void setReadRequestHandlers(
    PeripheralReadRequestResult? Function(
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    )?
    handler,
  ) {
    UniversalBlePeripheral.setReadRequestHandlers(handler);
  }

  @override
  void setWriteRequestHandlers(
    PeripheralWriteRequestResult Function(
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    )?
    handler,
  ) {
    UniversalBlePeripheral.setWriteRequestHandlers(handler);
  }

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    PeripheralPlatformConfig? platformConfig,
  }) {
    return UniversalBlePeripheral.startAdvertising(
      services: services,
      localName: localName,
      platformConfig: platformConfig,
    );
  }

  @override
  Future<void> stopAdvertising() {
    return UniversalBlePeripheral.stopAdvertising();
  }

  @override
  Future<void> clearServices() {
    return UniversalBlePeripheral.clearServices();
  }

  @override
  Future<PeripheralReadinessState> getAvailabilityState() {
    return UniversalBlePeripheral.getAvailabilityState();
  }

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) {
    return UniversalBlePeripheral.updateCharacteristicValue(
      characteristicId: characteristicId,
      value: value,
      deviceId: deviceId,
    );
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) {
    return UniversalBlePeripheral.getMaximumNotifyLength(deviceId);
  }
}

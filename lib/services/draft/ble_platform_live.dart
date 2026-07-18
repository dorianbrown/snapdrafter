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
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) {
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
  Stream<Uint8List> characteristicValueStream(String deviceId, String characteristicUuid) =>
      UniversalBle.characteristicValueStream(deviceId, characteristicUuid);

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
    return UniversalBle.unsubscribe(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
  }

  @override
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    Uint8List value,
  ) {
    return UniversalBle.write(
      deviceId,
      serviceUuid,
      characteristicUuid,
      value,
    );
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    return UniversalBle.read(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
  }
}

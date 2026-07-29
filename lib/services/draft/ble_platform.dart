import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

/// Abstract interface for BLE central operations.
///
/// [DraftBleFollower] delegates all platform-level BLE calls to an
/// implementation of this interface so that real hardware is not required
/// during testing.
abstract class BleCentral {
  /// Stream of scan results from BLE scanning.
  Stream<BleDevice> get scanStream;

  /// Starts a BLE scan for the given filter and platform configuration.
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig});

  /// Stops any in-progress BLE scan.
  Future<void> stopScan();

  /// Connects to the remote device at [deviceId].
  Future<void> connect(String deviceId);

  /// Disconnects from the remote device at [deviceId].
  Future<void> disconnect(String deviceId);

  /// Requests an MTU size for the given device.
  Future<int> requestMtu(String deviceId, int mtu);

  /// Discovers GATT services on the remote device.
  Future<List<BleService>> discoverServices(String deviceId);

  /// Stream of device connection state: `true` = connected, `false` = disconnected.
  Stream<bool> connectionStream(String deviceId);

  /// Stream of characteristic value updates for [characteristicUuid] on
  /// [deviceId]. Used to receive state push notifications from the leader.
  Stream<Uint8List> characteristicValueStream(String deviceId, String characteristicUuid);

  /// Subscribes to notifications for a characteristic on the remote device.
  Future<void> subscribeNotifications(String deviceId, String serviceUuid, String characteristicUuid);

  /// Subscribes to indications for a characteristic on the remote device.
  /// Indications require acknowledgment from the central, providing reliable
  /// delivery — critical for cross-platform BLE where notifications may be
  /// silently dropped (e.g. iOS peripheral → Android central).
  Future<void> subscribeIndications(String deviceId, String serviceUuid, String characteristicUuid);

  /// Unsubscribes from notifications for a characteristic on the remote device.
  Future<void> unsubscribe(String deviceId, String serviceUuid, String characteristicUuid);

  /// Writes a command payload to a characteristic on the remote device.
  Future<void> write(String deviceId, String serviceUuid, String characteristicUuid, Uint8List value);

  /// Reads a characteristic value from the remote device.
  Future<Uint8List> readCharacteristic(String deviceId, String serviceUuid, String characteristicUuid);
}

/// Abstract interface for BLE peripheral operations.
///
/// [DraftBleLeader] delegates all platform-level BLE calls to an
/// implementation of this interface so that real hardware is not required
/// during testing.
abstract class BlePeripheral {
  Stream<BlePeripheralConnectionStateChanged> get connectionStateStream;

  Stream<BlePeripheralCharacteristicSubscriptionChanged>
      get characteristicSubscriptionStream;

  Stream<BlePeripheralAdvertisingStateChanged> get advertisingStateStream;

  Stream<BlePeripheralMtuChanged> get mtuChangedStream;

  Future<BlePeripheralCapabilities> getCapabilities();

  Future<void> addService(BlePeripheralService service);

  void setReadRequestHandlers(
    PeripheralReadRequestResult? Function(
            String deviceId, String characteristicId, int offset, Uint8List? value)?
        handler,
  );

  void setWriteRequestHandlers(
    PeripheralWriteRequestResult Function(
            String deviceId, String characteristicId, int offset, Uint8List? value)?
        handler,
  );

  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    PeripheralPlatformConfig? platformConfig,
  });

  Future<void> stopAdvertising();

  Future<void> clearServices();

  Future<List<String>> getServices();

  Future<PeripheralReadinessState> getAvailabilityState();

  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  });

  Future<int?> getMaximumNotifyLength(String deviceId);
}

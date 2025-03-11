import 'dart:typed_data';
import 'dart:convert' show utf8;
import 'package:uuid/uuid.dart';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart' hide ConnectionState;


final deckUuid = UUID.short(100);
final seatUuid = UUID.short(101);
final deviceIdCharacteristicUuid = UUID.short(200);
final deviceIdUuid = Uuid(); // Random UUID, used to distinguish devices

class Advertiser {
  final _manager = PeripheralManager();

  // Init method
  Advertiser() {
    initialize();
  }

  void initialize() {
    _manager.stateChanged.listen((stateChange) {
      debugPrint("New Advertiser state: ${stateChange.state}");
      switch (stateChange.state) {
      // Requires authorization
        case BluetoothLowEnergyState.unauthorized:
          _manager.authorize();
      // Ready for advertising
        case BluetoothLowEnergyState.poweredOn:
          startAdvertising();
        default:
          _manager.stopAdvertising();
      }
    });
  }

  Future<void> startAdvertising() async {
    _manager.removeAllServices();
    final service = GATTService(
      uuid: seatUuid,
      isPrimary: true,
      includedServices: [],
      characteristics: [
        GATTCharacteristic.immutable(
            uuid: deviceIdCharacteristicUuid,
            value: utf8.encode(deviceIdUuid.toString()),
            descriptors: []
        ),
        GATTCharacteristic.mutable(
          uuid: UUID.short(201),
          properties: [
            GATTCharacteristicProperty.read,
            GATTCharacteristicProperty.write,
            GATTCharacteristicProperty.writeWithoutResponse,
            GATTCharacteristicProperty.notify,
            GATTCharacteristicProperty.indicate,
          ],
          permissions: [
            GATTCharacteristicPermission.read,
            GATTCharacteristicPermission.write,
          ],
          descriptors: [],
        ),
      ],
    );

    await _manager.addService(service);
    await _manager.startAdvertising(Advertisement(
        name: "DeckScanner Draft Peer",
        serviceUUIDs: [seatUuid]
    ));
    debugPrint("deviceIdCharacteristicUuid: ${deviceIdCharacteristicUuid.toString()}");
    debugPrint("deviceIdUuid: ${deviceIdUuid.toString()}");
  }
}

class Scanner {
  final _manager = CentralManager();
  final _draftPeers = [];

  Future<List<Peripheral>> get connectedDevices => _manager.retrieveConnectedPeripherals();

  // Init method
  Scanner() {
    initialize();
  }

  void initialize() {
    // Manage state changes to bluetooth
    _manager.stateChanged.listen((stateChange){
      debugPrint("New Scanner state: ${stateChange.state}");
      switch (stateChange.state) {
        case BluetoothLowEnergyState.unauthorized:
          _manager.authorize();
        case BluetoothLowEnergyState.poweredOn:
          startDeviceScanning();
        default:
          _manager.stopDiscovery();
      }
    });

    _manager.connectionStateChanged.listen((stateChange) {
      switch (stateChange.state) {
        case ConnectionState.connected:
          debugPrint("Connected to ${stateChange.peripheral}");
        case ConnectionState.disconnected:
          debugPrint("Disconnected from ${stateChange.peripheral}");
      }
    });

    _manager.discovered.listen((discovery) async {
      debugPrint("Discovered ${discovery.advertisement.name}");
      // Here we filter for relevant services
      await _manager.connect(discovery.peripheral);
      _manager.discoverGATT(discovery.peripheral).then((services) {
        debugPrint("Breakpoint");
      });
    });
  }

  startDeviceScanning() async {
    _manager.startDiscovery(serviceUUIDs: [seatUuid, deckUuid]);
  }
}
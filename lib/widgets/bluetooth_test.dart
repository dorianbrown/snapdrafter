import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;

// Unique UUID for this application. Used to detect other apps advertising
final deckUuid = ble.UUID.fromString("a4b65998-08fb-4e24-906e-82ba2c09a894");
final seatUuid = ble.UUID.fromString("8a4352fd-b97c-4f5d-a158-d3875afbf892");

class BluetoothTest extends StatefulWidget {
  const BluetoothTest({super.key});

  @override
  _BluetoothTestState createState() => _BluetoothTestState();
}
class _BluetoothTestState extends State<BluetoothTest> {
  late Future<void> _initializeBluetoothFuture;
  List<String> _currentDevices = [];
  bool _isAdvertising = false;
  late ble.PeripheralManager _advManager;

  @override
  void initState() {
    super.initState();
    _initializeBluetoothFuture = _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {

    // Request bluetooth permissions using permission_handler
    await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Permission.bluetooth
    ].request();

    // Setting up and starting BLE advertising
    _advManager = ble.PeripheralManager();

    await _advManager.startAdvertising(ble.Advertisement(
      name: "Advertisement_name"
    ));
  }

  Future<void> startBLEScanning() async {
    debugPrint("Need to implement scanning");
  }

  @override
  void dispose() {
    _advManager.stopAdvertising();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: Center(
        child: FutureBuilder(
            future: _initializeBluetoothFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              } else {
                return ListView(
                  children: [
                    TextButton(onPressed: startBLEScanning, child: Text("Scan")),
                    Text("Currently advertising: $_isAdvertising"),
                    for (final device in _currentDevices)
                      Text(device)
                  ],
                );
              }
            }
        )
      )
    );
  }
}
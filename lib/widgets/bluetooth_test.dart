import 'dart:typed_data';

import 'package:flutter/material.dart';
import '/utils/bluetooth_managers.dart';

class BluetoothTest extends StatefulWidget {
  const BluetoothTest({super.key});

  @override
  _BluetoothTestState createState() => _BluetoothTestState();
}
class _BluetoothTestState extends State<BluetoothTest> {
  late Advertiser _advertiser;
  late Scanner _scanner;
  List<String> _connectedDevices = [];

  @override
  void initState() {
    super.initState();
    _advertiser = Advertiser();
    _scanner = Scanner();
  }

  Future<void> getConnectedDevices() async {
    _scanner.connectedDevices.then((devices) {
      setState(() {
        _connectedDevices = devices.map((dev) => dev.uuid.toString()).toList();
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: Center(
        child: ListView(
          children: [
            TextButton(onPressed: getConnectedDevices, child: Text("Show connections")),
            for (final device in _connectedDevices)
              Text(device)
          ],
        )
      )
    );
  }
}
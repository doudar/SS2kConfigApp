import 'package:SS2kConfigApp/screens/settings_screen.dart';
import '../screens/shifter_screen.dart';
import 'package:flutter/material.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/extra.dart';

import 'dart:async';

class MainDeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const MainDeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<MainDeviceScreen> createState() => _MainDeviceScreenState();
}

class _MainDeviceScreenState extends State<MainDeviceScreen> {

  BLEData bleData = new BLEData();

  @override
  void initState() {
    super.initState();
    
    bleData.connectionStateSubscription = widget.device.connectionState.listen((state) async {
      bleData.connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        bleData.services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected && bleData.rssi == null) {
        bleData.rssi = await widget.device.readRssi();
      }
      if (mounted) {
        setState(() {});
      }
    });

    bleData.isConnectingSubscription = widget.device.isConnecting.listen((value) {
      bleData.isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    bleData.isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      bleData.isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    bleData.connectionStateSubscription.cancel();
    bleData.isConnectingSubscription.cancel();
    bleData.isDisconnectingSubscription.cancel();
    super.dispose();
  }

  buildShiftMenuButton(BuildContext context) {
    return OutlinedButton(
      child: const Text("Virtual Shifter", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ShifterScreen(device: widget.device, bleData: bleData,),
            //settings: RouteSettings(name: '/ShifterScreen'),
          ),
        );
      },
    );
  }

  buildSettingsButton(BuildContext context) {
    return OutlinedButton(
      child: const Text("Settings", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SettingsScreen(device: widget.device, bleData: bleData),
            //settings: RouteSettings(name: '/SettingsScreen'),
          ),
        );
      },
    );
  }

  buildUpdateButton(BuildContext context) {
    return OutlinedButton(
      child: const Text("Update Firmware", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SettingsScreen(device: widget.device, bleData: bleData,),
            //settings: RouteSettings(name: '/UpdateFirmwareScreen'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Row(children: <Widget>[
                buildShiftMenuButton(context),
                buildSettingsButton(context),
                buildUpdateButton(context),
              ], mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center),
            ],
          ),
        ),
      ),
    );
  }
}

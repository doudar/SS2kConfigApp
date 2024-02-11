import 'package:SS2kConfigApp/screens/settings_screen.dart';
import '../screens/shifter_screen.dart';
import 'package:flutter/material.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/extra.dart';
import '../utils/customcharhelpers.dart';
import '../utils/constants.dart';

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
      if (state == BluetoothConnectionState.connected && bleData.charReceived == false) {
        await discoverServices();
        await _findChar();
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
    //bleData.connectionStateSubscription.cancel();
    //bleData.isConnectingSubscription.cancel();
    //bleData.isDisconnectingSubscription.cancel();
    super.dispose();
  }

  Future _findChar() async {
    while (!this.bleData.charReceived) {
      try {
        BluetoothService cs = this.bleData.services.first;
        for (BluetoothService s in this.bleData.services) {
          if (s.uuid == Guid(csUUID)) {
            cs = s;
            break;
          }
        }
        List<BluetoothCharacteristic> characteristics = cs.characteristics;
        for (BluetoothCharacteristic c in characteristics) {
          if (c.uuid == Guid(ccUUID)) {
            this.bleData.myCharacteristic = c;
            break;
          }
        }
        this.bleData.charReceived = true;
      } catch (e) {}
    }
  }

  Future discoverServices() async {
    if (mounted) {
      setState(() {
        this.bleData.isDiscoveringServices = true;
      });
    }
    if (widget.device.isConnected) {
      try {
        this.bleData.services = await widget.device.discoverServices();
        _findChar();
        await updateCustomCharacter(this.bleData, true);
        //Snackbar.show(ABC.c, "Discover Services: Success", success: true);
      } catch (e) {
        //Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
      }
    }
    if (mounted) {
      setState(() {
        this.bleData.isDiscoveringServices = false;
      });
    }
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
            builder: (context) => ShifterScreen(
              device: widget.device,
              bleData: bleData,
            ),
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
            builder: (context) => SettingsScreen(
              device: widget.device,
              bleData: bleData,
            ),
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

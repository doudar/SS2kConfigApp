import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';
import '../utils/customcharhelpers.dart';
import '../utils/bledata.dart';

class DeviceHeader extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;
  final bool connectOnly;
  const DeviceHeader({Key? key, required this.device, required this.bleData, this.connectOnly = false})
      : super(key: key);

  @override
  State<DeviceHeader> createState() => _DeviceHeaderState();
}

class _DeviceHeaderState extends State<DeviceHeader> {
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late Timer rssiTimer;

  @override
  void initState() {
    super.initState();
    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      if (mounted) {
        if (widget.device.isConnected) {
          widget.bleData.rssi.value = await widget.device.readRssi();
        } else {
          widget.bleData.rssi.value = 0;
        }
        setState(() {});
      }
      rssiTimer = Timer.periodic(Duration(seconds: 10), (rssiTimer) async {
        if (widget.device.isConnected) {
          try {
            widget.bleData.rssi.value = await widget.device.readRssi();
          } catch (e) {
            widget.bleData.rssi.value = 0;
          }
        }
        if (mounted) {
          setState(() {});
        }
      });
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    rssiTimer.cancel();

    super.dispose();
  }

  bool get isConnected {
    return widget.bleData.connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
      await onDiscoverServicesPressed();
    } catch (e) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
      }
    }
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e), success: false);
    }
  }

  Future onDiscoverServicesPressed() async {
    if (mounted) {
      setState(() {
        widget.bleData.isReadingOrWriting.value = true;
      });
    }
    try {
      widget.bleData.services = await widget.device.discoverServices();
      //await _findChar();
      await updateCustomCharacter(widget.bleData, widget.device);
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
    }
    if (mounted) {
      setState(() {
        widget.bleData.isReadingOrWriting.value = false;
      });
    }
  }

  Future onSaveSettingsPressed() async {
    try {
      await saveAllSettings(widget.bleData, widget.device);
      Snackbar.show(ABC.c, "Settings Saved", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Save Settings Failed ", e), success: false);
    }
  }

  Future onSaveLocalPressed() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user', jsonEncode(widget.bleData.customCharacteristic));
      Snackbar.show(ABC.c, "Settings Saved", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Save Local Failed ", e), success: false);
    }
  }

  Future onLoadLocalPressed() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      widget.bleData.customCharacteristic = jsonDecode(prefs.getString('user')!);
      Snackbar.show(ABC.c, "Settings Loaded", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Load local failed. Do you have a backup?", e), success: false);
    }
  }

  Future onRebootPressed() async {
    try {
      await reboot(widget.bleData, widget.device);
      Snackbar.show(ABC.a, "SmartSpin2k is rebooting", success: true);
      await onDisconnectPressed();
      await onConnectPressed();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reboot Failed ", e), success: false);
    }
  }

  Future onResetPressed() async {
    try {
      await resetToDefaults(widget.bleData, widget.device);
      await discoverServices();
      Snackbar.show(ABC.c, "SmartSpin2k has been reset to defaults", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reset Failed ", e), success: false);
    }
  }

  Future discoverServices() async {
    if (mounted) {
      setState(() {
        widget.bleData.isReadingOrWriting.value = true;
      });
    }
    if (widget.device.isConnected) {
      try {
        widget.bleData.services = await widget.device.discoverServices();
        //_findChar();
        await updateCustomCharacter(widget.bleData, widget.device);
        Snackbar.show(ABC.c, "Discover Services: Success", success: true);
      } catch (e) {
        Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
      }
    }
    if (mounted) {
      setState(() {
        widget.bleData.isReadingOrWriting.value = false;
      });
    }
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: CircularProgressIndicator(
          //backgroundColor: Colors.black12,
          //color: Colors.black26,
          ),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${widget.device.remoteId}'),
    );
  }

  Widget buildRssiTile(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isConnected ? const Icon(Icons.bluetooth_connected) : const Icon(Icons.bluetooth_disabled),
        Text('${widget.bleData.rssi.value} dBm', style: Theme.of(context).textTheme.bodySmall)
      ],
    );
  }

  Widget buildUpdateValues(BuildContext context) {
    return IndexedStack(
      index: (widget.bleData.isReadingOrWriting.value) ? 1 : 0,
      children: <Widget>[
        isConnected
            ? OutlinedButton(
                child: const Text("Refresh\nValues", textAlign: TextAlign.center),
                onPressed: onDiscoverServicesPressed,
              )
            : Text(" "),
        const IconButton(
          icon: SizedBox(
            child: CircularProgressIndicator(
                //valueColor: AlwaysStoppedAnimation(Colors.grey),
                ),
            width: 18.0,
            height: 18.0,
          ),
          onPressed: null,
        )
      ],
    );
  }

  Widget buildSaveButton(context) {
    return OutlinedButton(
      child: const Text("Save To\nSS2k", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        onSaveSettingsPressed();
        setState(() {});
      },
    );
  }

  Widget buildSaveLocalButton(context) {
    return OutlinedButton(
        child: const Text("Backup\nSettings", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 16, 3, 255),
        ),
        onPressed: () {
          onSaveLocalPressed();
          setState(
            () {},
          );
        });
  }

  Widget buildLoadLocalButton(context) {
    return OutlinedButton(
        child: const Text("Load\nBackup", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 16, 3, 255),
        ),
        onPressed: () {
          onLoadLocalPressed();
          setState(() {});
        });
  }

  Future waitToSetState(context) async {
    await Future.delayed(Duration(seconds: 10));
    try {
      //Can fail if navigation happens within 10 seconds
      setState(() {});
    } catch (e) {}
    ;
  }

  buildRebootButton(context) {
    return OutlinedButton(
        child: const Text(" Reboot\nSS2k ", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 255, 3, 3),
        ),
        onPressed: () {
          onRebootPressed();
          waitToSetState(context);
        });
  }

  buildResetButton(context) {
    return OutlinedButton(
        child: const Text("Set\nDefaults", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 225, 214, 10),
        ),
        onPressed: () {
          onResetPressed();
          setState(() {});
        });
  }

  // Future _findChar() async {
  //   while (!widget.bleData.charReceived) {
  //     try {
  //       BluetoothService cs = widget.bleData.services.first;
  //       for (BluetoothService s in widget.bleData.services) {
  //         if (s.uuid == Guid(csUUID)) {
  //           cs = s;
  //           break;
  //         }
  //       }
  //       List<BluetoothCharacteristic> characteristics = cs.characteristics;
  //       for (BluetoothCharacteristic c in characteristics) {
  //         if (c.uuid == Guid(ccUUID)) {
  //           widget.bleData.getMyCharacteristic(device) = c;
  //           break;
  //         }
  //       }
  //       widget.bleData.charReceived = true;
  //     } catch (e) {
  //       Snackbar.show(ABC.c, prettyException("No Services", e), success: false);
  //     }
  //   }
  // }

  Widget buildConnectButton(BuildContext context) {
    return Row(
      children: [
        (widget.bleData.isConnecting || widget.bleData.isDisconnecting)
            ? buildSpinner(context)
            : OutlinedButton(
                onPressed: (isConnected ? onDisconnectPressed : onConnectPressed),
                child: Text((isConnected ? "DISCONNECT" : "CONNECT"),
                    textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
                style: isConnected
                    ? OutlinedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 255, 3, 3),
                      )
                    : OutlinedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 25, 113, 0),
                      ))
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      ListTile(
        leading: buildRssiTile(context),
        title: buildConnectButton(context),
        trailing: widget.connectOnly ? SizedBox() : buildUpdateValues(context),
        titleAlignment: ListTileTitleAlignment.threeLine,
      ),
      (isConnected && !widget.connectOnly)
          ? Column(children: <Widget>[
              Row(children: <Widget>[
                buildRebootButton(context),
                buildResetButton(context),
                buildSaveButton(context),
              ], mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center),
              Row(children: <Widget>[
                buildSaveLocalButton(context),
                buildLoadLocalButton(context),
              ], mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center),
            ])
          : SizedBox(),
      Divider(height: 5),
    ]);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_example/utils/extra.dart';

import '../widgets/service_tile.dart';
import '../widgets/characteristic_tile.dart';
import '../widgets/descriptor_tile.dart';
import '../utils/snackbar.dart';
import '../utils/constants.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  int? _rssi;
  int? _mtuSize;
  int? charReceived;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];

  bool _isDiscoveringServices = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;
  late StreamSubscription<int> _mtuSubscription;

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        _services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected && _rssi == null) {
        _rssi = await widget.device.readRssi();
      }
      if (mounted) {
        setState(() {});
      }
    });

    _mtuSubscription = widget.device.mtu.listen((value) {
      _mtuSize = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _mtuSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
    } catch (e) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
      }
    }
  }

  Future onCancelPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream(queue: false);
      Snackbar.show(ABC.c, "Cancel: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Cancel Error:", e), success: false);
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
        _isDiscoveringServices = true;
      });
    }
    try {
      _services = await widget.device.discoverServices();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Future discoverServices() async {
    if (mounted) {
      setState(() {
        _isDiscoveringServices = true;
      });
    }
    try {
      _services = await widget.device.discoverServices();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Future onRequestMtuPressed() async {
    try {
      await widget.device.requestMtu(223, predelay: 0);
      Snackbar.show(ABC.c, "Request Mtu: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Change Mtu Error:", e), success: false);
    }
  }

  List<Widget> _buildServiceTiles(BuildContext context, BluetoothDevice d) {
    return _services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics.map((c) => _buildCharacteristicTile(c)).toList(),
          ),
        )
        .toList();
  }

  CharacteristicTile _buildCharacteristicTile(BluetoothCharacteristic c) {
    return CharacteristicTile(
      characteristic: c,
      descriptorTiles: c.descriptors.map((d) => DescriptorTile(descriptor: d)).toList(),
    );
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: CircularProgressIndicator(
          backgroundColor: Colors.black12,
          color: Colors.black26,
        ),
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
        Text(((isConnected && _rssi != null) ? '${_rssi!} dBm' : ''), style: Theme.of(context).textTheme.bodySmall)
      ],
    );
  }

  Widget buildGetServices(BuildContext context) {
    return IndexedStack(
      index: (_isDiscoveringServices) ? 1 : 0,
      children: <Widget>[
        TextButton(
          child: const Text("Update Values"),
          onPressed: onDiscoverServicesPressed,
        ),
        const IconButton(
          icon: SizedBox(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.grey),
            ),
            width: 18.0,
            height: 18.0,
          ),
          onPressed: null,
        )
      ],
    );
  }

  String readCC(Map c) {
    return (c["value"].toString());
  }

  Future writeCC(BluetoothCharacteristic cc, List<int> value) async {
    //List<int> ret = [0];
    try {
      await cc.write(value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $value", success: false);
    }
  }

  Future notify(BluetoothCharacteristic cc) async {
    final subscription = cc.onValueReceived.listen((value) {
      if (value[0] == 0x80) {
        var length = value.length;
        var t = new Uint8List(length);
        String logString = "";
        //
        for (var c in customCharacteristic) {
          if (int.parse(c["reference"]) == value[1]) {
            for (var i = 0; i < length; i++) {
              t[i] = value[i];
            }
            var data = t.buffer.asByteData();

            switch (c["type"]) {
              case "int":
                {
                  c["value"] = data.getUint16(2, Endian.little);
                  logString = c["value"].toString();
                  break;
                }
              case "bool":
                {
                  c["value"] = value[2];
                  logString = c["value"].toString();
                  break;
                }
              case "float":
                {
                  c["value"] = data.getUint16(2, Endian.little);
                  logString = c["value"].toString();
                  break;
                }
              case "long":
                {
                  c["value"] = data.getUint32(2, Endian.little);
                  logString = c["value"].toString();
                  break;
                }
              case "String":
                {
                  List<int> reversed = value.reversed.toList();
                  reversed.removeRange(length - 2, length);
                  try {
                    c["value"] = utf8.decode(reversed);
                  } catch (e) {
                    Snackbar.show(ABC.c, "Failed to decode string", success: false);
                  }
                  logString = c["value"].toString();
                  break;
                }
              default:
                {
                  String type = c["type"];
                  print("No decoder found for $type");
                }
            }

            break;
          }
        }

        print("Received value: $logString");
      } else if (value[0] == 0xff) {
        for (var c in customCharacteristic) {
          if (int.parse(c["reference"]) == value[1]) {
            c["value"] = "Not supported by firmware version.";
          }
        }
      }
    });
    widget.device.cancelWhenDisconnected(subscription);
    if (!cc.isNotifying) {
      try {
        await cc.setNotifyValue(true);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to subscribe to notifications", success: false);
      }
    }
  }

//Build the settings dropdowns
  List<Widget> buildSettings(BuildContext context) {
    List<Widget> settings = [];
    try {
      BluetoothService cs = _services[0];
      BluetoothCharacteristic cc = cs.characteristics[0];

      for (BluetoothService s in _services) {
        if (s.uuid == Guid(csUUID)) {
          cs = s;
          break;
        }
      }
      List<BluetoothCharacteristic> characteristics = cs.characteristics;
      for (BluetoothCharacteristic c in characteristics) {
        if (c.uuid == Guid(ccUUID)) {
          cc = c;
          break;
        }
      }

      notify(cc);

      newEntry(Map c) {
        if (c["isSetting"]) {
          //read settings
          writeCC(cc, [0x01, int.parse(c["reference"])]);
          //await readCC(c);
          settings.add(ListTile(
            contentPadding: const EdgeInsets.all(16.0),
            //leading: Text(c["vName"]),
            title: Text(c["vName"]),
            trailing: Text(c["value"].toString()),
          ));
          //setState(() {});
        }
      }

      customCharacteristic.forEach((c) => newEntry(c));
    } catch (e) {
      Snackbar.show(ABC.c, "Couldn't find service", success: false);
    }
    //here
    return settings;
  }

  Widget buildMtuTile(BuildContext context) {
    return ListTile(
        title: const Text('MTU Size'),
        subtitle: Text('$_mtuSize bytes'),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: onRequestMtuPressed,
        ));
  }

  Widget buildConnectButton(BuildContext context) {
    return Row(children: [
      if (_isConnecting || _isDisconnecting) buildSpinner(context),
      TextButton(
          onPressed: _isConnecting ? onCancelPressed : (isConnected ? onDisconnectPressed : onConnectPressed),
          child: Text(
            _isConnecting ? "CANCEL" : (isConnected ? "DISCONNECT" : "CONNECT"),
            style: Theme.of(context).primaryTextTheme.labelLarge?.copyWith(color: Colors.white),
          ))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    try {
      BluetoothService test = _services[0];
    } catch (e) {
      discoverServices();
    }
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          //actions: [buildConnectButton(context)],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              buildRemoteId(context),
              ListTile(
                leading: buildRssiTile(context),
                title: Text('Device is ${_connectionState.toString().split('.')[1]}.'),
                trailing: buildGetServices(context),
              ),
              buildMtuTile(context),
              //..._buildServiceTiles(context, widget.device),
              ...buildSettings(context),
            ],
          ),
        ),
      ),
    );
  }
}

/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ScanResultTile extends StatefulWidget {
  const ScanResultTile({Key? key, required this.result, this.onTap}) : super(key: key);

  final ScanResult result;
  final VoidCallback? onTap;

  @override
  State<ScanResultTile> createState() => _ScanResultTileState();
}

class _ScanResultTileState extends State<ScanResultTile> {
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  @override
  void initState() {
    super.initState();
    _connectionStateSubscription = this.widget.result.device.connectionState.listen((state) {
      _connectionState = state;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    super.dispose();
  }

  String getNiceHexArray(List<int> bytes) {
    return '[${bytes.map((i) => i.toRadixString(16).padLeft(2, '0')).join(', ')}]';
  }

  String getNiceManufacturerData(Map<int, List<int>> data) {
    return data.entries
        .map((entry) => '${entry.key.toRadixString(16)}: ${getNiceHexArray(entry.value)}')
        .join(', ')
        .toUpperCase();
  }

  String getNiceServiceData(Map<Guid, List<int>> data) {
    return data.entries.map((v) => '${v.key}: ${getNiceHexArray(v.value)}').join(', ').toUpperCase();
  }

  String getNiceServiceUuids(List<Guid> serviceUuids) {
    return serviceUuids.join(', ').toUpperCase();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Widget _buildTitle(BuildContext context) {
    if (this.widget.result.device.platformName.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.max,
        //mainAxisAlignment: MainAxisAlignment.start,
        //crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(this.widget.result.device.advName,
              overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
          _rssiRow(context),
        ],
      );
    } else {
      return Text(this.widget.result.device.remoteId.toString());
    }
  }

  Widget _buildConnectButton(BuildContext context) {
    return ElevatedButton(
      child: isConnected ? const Text('OPEN') : const Text('CONNECT'),
      onPressed: (this.widget.result.advertisementData.connectable) ? this.widget.onTap : null,
      style: ElevatedButton.styleFrom(
          backgroundColor: ThemeData().colorScheme.secondary, foregroundColor: ThemeData().colorScheme.onSecondary),
    );
  }

  Widget _buildAdvRow(BuildContext context, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(
            width: 12.0,
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.apply(color: Colors.black),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor(int index) {
    // Define the thresholds for signal strength
    final int worstRSSI = -100; // Adjust this based on your requirement
    final int bestRSSI = -60; // Adjust this based on your requirement
    final int signalStrength = (index + 1) * 2;

    // Interpolate the color based on RSSI value
    final double ratio = 2* (signalStrength - worstRSSI) / (bestRSSI - worstRSSI);
    final int red = (255 * (1 - ratio)).toInt();
    final int green = (255 * ratio).toInt();

    // Return the color based on interpolation
    return Color.fromRGBO(red, green, 0, 1.0);
  }

  Widget _rssiRow(BuildContext context) {
    int numBoxesToShow = ((this.widget.result.rssi + 100) / 2.5).ceil();
    return Row(
      children: [
        Text(
          'Signal strength:',
          style: TextStyle(fontSize: 12, color: ThemeData().colorScheme.onBackground),
        ),
        SizedBox(width: 8),
        Row(
          children: List.generate(10, (index) {
            if (index < numBoxesToShow) {
              return Container(
                width: 5,
                height: 10,
                margin: EdgeInsets.symmetric(horizontal: 1),
                color: _getColor(index),
              );
            } else {
              return Container(
                width: 5,
                height: 10,
                margin: EdgeInsets.symmetric(horizontal: 1),
                color: Colors.transparent,
              );
            }
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var adv = this.widget.result.advertisementData;
    return ExpansionTile(
      title: _buildTitle(context),
      leading: Image.asset(
        'assets/ss2kv3.png',
      ),
      trailing: _buildConnectButton(context),
      children: <Widget>[
        if (adv.advName.isNotEmpty) _buildAdvRow(context, 'Name', adv.advName),
        _buildAdvRow(context, 'RSSI', '${this.widget.result.rssi.toString()}'),
      ],
    );
  }
}

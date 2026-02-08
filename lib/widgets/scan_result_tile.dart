/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../utils/extra.dart';
import '../utils/snackbar.dart';

class ScanResultTile extends StatefulWidget {
  const ScanResultTile({Key? key, required this.device, this.onTap}) : super(key: key);

  final BleDevice device;
  final VoidCallback? onTap;

  @override
  State<ScanResultTile> createState() => _ScanResultTileState();
}

class _ScanResultTileState extends State<ScanResultTile> {
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  StreamSubscription<bool>? _connectionStateSubscription;
  StreamSubscription<bool>? _connectingSubscription;
  StreamSubscription<bool>? _disconnectingSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialConnectionState();
    _connectionStateSubscription = UniversalBle.connectionStream(widget.device.deviceId).listen((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });
    _connectingSubscription = widget.device.isConnecting.listen((value) {
      if (!mounted) return;
      setState(() => _isConnecting = value);
    });
    _disconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      if (!mounted) return;
      setState(() => _isDisconnecting = value);
    });
  }

  Future<void> _loadInitialConnectionState() async {
    try {
      final state = await UniversalBle.getConnectionState(widget.device.deviceId);
      if (!mounted) return;
      setState(() => _isConnected = state == BleConnectionState.connected);
    } catch (_) {
      // Ignore failures when determining initial state
    }
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _connectingSubscription?.cancel();
    _disconnectingSubscription?.cancel();
    super.dispose();
  }

  String _niceHexArray(Uint8List bytes) {
    if (bytes.isEmpty) return '[]';
    final parts = bytes.map((i) => i.toRadixString(16).padLeft(2, '0')).join(', ');
    return '[$parts]';
  }

  String? _manufacturerSummary() {
    if (widget.device.manufacturerDataList.isEmpty) return null;
    return widget.device.manufacturerDataList
        .map((entry) => '${entry.companyIdRadix16}: ${_niceHexArray(entry.payload)}')
        .join(', ')
        .toUpperCase();
  }

  String? _serviceUuidSummary() {
    if (widget.device.services.isEmpty) return null;
    return widget.device.services.join(', ').toUpperCase();
  }

  Widget _buildTitle(BuildContext context) {
    final displayName = widget.device.name?.isNotEmpty == true ? widget.device.name! : widget.device.deviceId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(displayName, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
        _rssiRow(context),
      ],
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    final theme = Theme.of(context);
    if (_isConnected) {
      return Container(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              child: const Text('OPEN'),
              onPressed: _isDisconnecting ? null : widget.onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.onSecondary,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: () async {
                if (_isDisconnecting) return;
                try {
                  await UniversalBle.disconnect(widget.device.deviceId);
                } catch (e) {
                  Snackbar.show(ABC.b, prettyException('Disconnect Error:', e), success: false);
                }
              },
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.onError,
                foregroundColor: theme.colorScheme.error,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ],
        ),
      );
    } else {
      return ElevatedButton(
        child: _isConnecting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('CONNECT'),
        onPressed: _isConnecting ? null : widget.onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.secondary,
          foregroundColor: theme.colorScheme.onSecondary,
        ),
      );
    }
  }

  Widget _buildAdvRow(BuildContext context, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12.0),
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
    const int worstRSSI = -100;
    const int bestRSSI = -60;
    final int signalStrength = (index + 1) * 2;
    final double ratio = 2 * (signalStrength - worstRSSI) / (bestRSSI - worstRSSI);
    final int red = (255 * (1 - ratio)).clamp(0, 255).toInt();
    final int green = (255 * ratio).clamp(0, 255).toInt();
    return Color.fromRGBO(red, green, 0, 1.0);
  }

  Widget _rssiRow(BuildContext context) {
    final rssi = widget.device.rssi ?? -100;
    final int numBoxesToShow = ((rssi + 100) / 2.5).ceil().clamp(0, 10).toInt();
    return Row(
      children: [
        Text(
          'Signal strength:',
          style: TextStyle(fontSize: 12, color: ThemeData().colorScheme.onSurface),
        ),
        const SizedBox(width: 8),
        Row(
          children: List.generate(10, (index) {
            if (index < numBoxesToShow) {
              return Container(
                width: 5,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: _getColor(index),
              );
            } else {
              return Container(
                width: 5,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 1),
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
    return ExpansionTile(
      title: _buildTitle(context),
      leading: Image.asset('assets/ss2kv3.png'),
      trailing: SizedBox(
        width: 120,
        child: _buildConnectButton(context),
      ),
      children: <Widget>[
        if (widget.device.name?.isNotEmpty == true) _buildAdvRow(context, 'Name', widget.device.name!),
        if (widget.device.rssi != null) _buildAdvRow(context, 'RSSI', '${widget.device.rssi}'),
        if (_serviceUuidSummary() != null) _buildAdvRow(context, 'Services', _serviceUuidSummary()!),
        if (_manufacturerSummary() != null) _buildAdvRow(context, 'Manufacturer', _manufacturerSummary()!),
        _buildAdvRow(context, 'Device ID', widget.device.deviceId),
      ],
    );
  }
}

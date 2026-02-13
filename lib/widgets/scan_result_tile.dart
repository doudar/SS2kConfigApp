/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/bledata.dart';
import '../utils/extra.dart';

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

  Color _tileAccent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (colorScheme.brightness == Brightness.light) {
      return const Color(0xFFB71C1C);
    }
    return colorScheme.error;
  }

  TextStyle? _deviceNameStyle(BuildContext context, {double? fontSize}) {
    final isLight = Theme.of(context).colorScheme.brightness == Brightness.light;
    return Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: isLight ? 0.90 : 0.75),
              blurRadius: isLight ? 7 : 5,
              offset: const Offset(0, 1),
            ),
          ],
        );
  }

  Widget _buildDeviceNameText(BuildContext context, String value) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsiveFontSize = (constraints.maxWidth * 0.09).clamp(14.0, 22.0).toDouble();
        return Text(
          value,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: _deviceNameStyle(context, fontSize: responsiveFontSize),
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context) {
    if (this.widget.result.device.platformName.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        //mainAxisAlignment: MainAxisAlignment.start,
        //crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildDeviceNameText(context, this.widget.result.device.advName),
          _rssiRow(context),
        ],
      );
    } else {
      return _buildDeviceNameText(context, this.widget.result.device.remoteId.toString());
    }
  }

  Widget _buildConnectButton(BuildContext context, {required bool compact}) {
    final accentColor = _tileAccent(context);
    final accentDark = Color.alphaBlend(Colors.black.withValues(alpha: 0.45), accentColor);

    final buttonPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final disconnectPadding = compact
      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10)
      : const EdgeInsets.symmetric(horizontal: 10, vertical: 10);

    if (isConnected) {
      return Container(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              child: const Text('OPEN'),
              onPressed: (this.widget.result.advertisementData.connectable) ? this.widget.onTap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentDark.withValues(alpha: 0.92),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: buttonPadding,
                minimumSize: compact ? const Size(0, 36) : null,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              child: Text(
                'Disconnect',
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600),
              ),
              onPressed: () async {
                // Set user-initiated disconnect flag
                BLEDataManager.forDevice(this.widget.result.device).isUserDisconnect = true;
                await this.widget.result.device.disconnectAndUpdateStream();
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
                padding: disconnectPadding,
                minimumSize: compact ? const Size(0, 36) : null,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    } else {
      return ElevatedButton(
        child: const Text('CONNECT'),
        onPressed: (this.widget.result.advertisementData.connectable) ? this.widget.onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentDark.withValues(alpha: 0.92),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: buttonPadding,
          minimumSize: compact ? const Size(0, 36) : null,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          const SizedBox(
            width: 12.0,
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
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
    final double ratio = 2 * (signalStrength - worstRSSI) / (bestRSSI - worstRSSI);
    final int red = (255 * (1 - ratio)).toInt();
    final int green = (255 * ratio).toInt();

    // Return the color based on interpolation
    return Color.fromRGBO(red, green, 0, 1.0);
  }

  Widget _rssiRow(BuildContext context) {
    int numBoxesToShow = ((this.widget.result.rssi + 100) / 2.5).ceil();

    Widget bars = Row(
      mainAxisSize: MainAxisSize.min,
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 210;
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!compact)
              Text(
                'Signal strength:',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85)),
              ),
            bars,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _tileAccent(context);
    final accentDark = Color.alphaBlend(Colors.black.withValues(alpha: 0.2), accentColor);

    var adv = this.widget.result.advertisementData;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final trailingWidth = isConnected
            ? (constraints.maxWidth * (compact ? 0.56 : 0.46)).clamp(170.0, 260.0).toDouble()
            : (constraints.maxWidth * (compact ? 0.32 : 0.28)).clamp(86.0, 132.0).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 1.1, sigmaY: 1.1),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accentDark.withValues(alpha: 0.82),
                      Colors.black.withValues(alpha: 0.64),
                    ],
                  ),
                  border: Border.all(color: accentColor.withValues(alpha: 0.38)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: _buildTitle(context),
                    leading: Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset('assets/ss2kv3.png'),
                    ),
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: _buildConnectButton(context, compact: compact),
                    ),
                    collapsedIconColor: Colors.white,
                    iconColor: Colors.white,
                    textColor: Colors.white,
                    collapsedTextColor: Colors.white,
                    children: <Widget>[
                      if (adv.advName.isNotEmpty) _buildAdvRow(context, 'Name', adv.advName),
                      _buildAdvRow(context, 'RSSI', '${this.widget.result.rssi.toString()}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

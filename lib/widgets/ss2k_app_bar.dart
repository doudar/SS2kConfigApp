import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'device_header.dart';

class SS2KAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BleDevice device;
  final String title;
  final List<Widget>? actions;
  final bool showDeviceHeader;

  const SS2KAppBar({
    Key? key,
    required this.device,
    required this.title,
    this.actions,
    this.showDeviceHeader = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600; // Threshold for narrow screens

        return AppBar(
          titleSpacing: 0,
          leadingWidth: 40.0,
          automaticallyImplyLeading: true,
          title: isNarrow
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title),
                    if (showDeviceHeader)
                      DeviceHeader(device: device, connectOnly: true),
                  ],
                )
              : Stack(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: showDeviceHeader
                          ? DeviceHeader(device: device, connectOnly: true)
                          : null,
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Text(title),
                    ),
                  ],
                ),
          centerTitle: true,
          actions: actions,
        );
      },
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

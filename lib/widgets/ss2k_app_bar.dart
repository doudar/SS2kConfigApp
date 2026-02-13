import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'device_header.dart';

class SS2KAppBar extends StatelessWidget implements PreferredSizeWidget {
  final BluetoothDevice device;
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

  double _computeAdaptiveHeight({
    required bool isNarrow,
    required double textScaleFactor,
  }) {
    if (!showDeviceHeader || !isNarrow) return kToolbarHeight;

    final clampedScale = textScaleFactor.clamp(1.0, 1.6);
    final scaleDelta = clampedScale - 1.0;
    final extraHeight = scaleDelta * 28.0;
    return (86.0 + extraHeight).clamp(86.0, 104.0);
  }

  bool get _isLikelyNarrowScreen {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    return logicalWidth < 600;
  }

  double get _systemTextScaleFactor {
    return WidgetsBinding.instance.platformDispatcher.textScaleFactor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600; // Threshold for narrow screens
        final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
        final double appBarHeight = _computeAdaptiveHeight(
          isNarrow: isNarrow,
          textScaleFactor: textScaleFactor,
        );

        return AppBar(
          toolbarHeight: appBarHeight,
          elevation: 0,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          titleSpacing: 0,
          leadingWidth: 40.0,
          automaticallyImplyLeading: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.92),
                  Colors.red.withValues(alpha: 0.40),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.red.withValues(alpha: 0.35),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          title: isNarrow
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                    if (showDeviceHeader)
                      const SizedBox(height: 2),
                    if (showDeviceHeader)
                      DeviceHeader(device: device, connectOnly: true),
                  ],
                )
              : Stack(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: showDeviceHeader
                          ? Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: DeviceHeader(device: device, connectOnly: true),
                            )
                          : null,
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
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
  Size get preferredSize => Size.fromHeight(
        _computeAdaptiveHeight(
          isNarrow: _isLikelyNarrowScreen,
          textScaleFactor: _systemTextScaleFactor,
        ),
      );
}

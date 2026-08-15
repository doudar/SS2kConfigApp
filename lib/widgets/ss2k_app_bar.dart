import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'device_header.dart';

class SS2KAppBar extends StatelessWidget implements PreferredSizeWidget {
  static const int _maxTitleLength = 36;

  final BluetoothDevice device;
  final String title;
  final List<Widget>? actions;
  final bool showDeviceHeader;
  final bool firmwareOnlyDeviceHeader;
  final bool deviceHeaderCustomRefreshEnabled;
  final bool backNavigationEnabled;

  const SS2KAppBar({
    Key? key,
    required this.device,
    required this.title,
    this.actions,
    this.showDeviceHeader = true,
    this.firmwareOnlyDeviceHeader = false,
    this.deviceHeaderCustomRefreshEnabled = true,
    this.backNavigationEnabled = true,
  }) : super(key: key);

  double _computeAdaptiveHeight({
    required bool isNarrow,
    required double textScaleFactor,
  }) {
    if (_isLongTitle && !showDeviceHeader) {
      return 72.0;
    }

    if (!showDeviceHeader || !isNarrow) return kToolbarHeight;

    final clampedScale = textScaleFactor.clamp(1.0, 1.6);
    final scaleDelta = clampedScale - 1.0;
    final extraHeight = scaleDelta * 28.0;
    final baseHeight = _isLongTitle ? 104.0 : 86.0;
    return (baseHeight + extraHeight).clamp(baseHeight, 122.0);
  }

  bool get _isLikelyNarrowScreen {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
    return logicalHeight > logicalWidth;
  }

  bool get _isLongTitle => title.length > _maxTitleLength;

  String get _displayTitle {
    if (!_isLongTitle) {
      return title;
    }
    return _splitAtMiddleSpace(title);
  }

  String _splitAtMiddleSpace(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final middle = trimmed.length ~/ 2;
    int? bestSpaceIndex;
    int bestDistance = trimmed.length;

    for (int index = 0; index < trimmed.length; index++) {
      if (trimmed[index] != ' ') {
        continue;
      }
      final distance = (index - middle).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSpaceIndex = index;
      }
    }

    if (bestSpaceIndex == null) {
      return '${trimmed.substring(0, middle)}\n${trimmed.substring(middle)}';
    }

    final firstLine = trimmed.substring(0, bestSpaceIndex).trimRight();
    final secondLine = trimmed.substring(bestSpaceIndex + 1).trimLeft();

    if (firstLine.isEmpty || secondLine.isEmpty) {
      return '${trimmed.substring(0, middle)}\n${trimmed.substring(middle)}';
    }

    return '$firstLine\n$secondLine';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isNarrow = size.height > size.width;
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
      automaticallyImplyLeading: backNavigationEnabled,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.92),
              Colors.red.withValues(alpha: 0.40),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
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
                  _displayTitle,
                  maxLines: _isLongTitle ? 2 : 1,
                  softWrap: _isLongTitle,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      (_isLongTitle
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                ),
                if (showDeviceHeader) const SizedBox(height: 2),
                if (showDeviceHeader)
                  DeviceHeader(
                    device: device,
                    connectOnly: true,
                    firmwareOnlyRefresh: firmwareOnlyDeviceHeader,
                    customRefreshEnabled: deviceHeaderCustomRefreshEnabled,
                  ),
              ],
            )
          : Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: showDeviceHeader
                      ? Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: DeviceHeader(
                            device: device,
                            connectOnly: true,
                            firmwareOnlyRefresh: firmwareOnlyDeviceHeader,
                            customRefreshEnabled:
                                deviceHeaderCustomRefreshEnabled,
                          ),
                        )
                      : null,
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    _displayTitle,
                    maxLines: _isLongTitle ? 2 : 1,
                    softWrap: _isLongTitle,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:
                        (_isLongTitle
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.titleLarge)
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: const [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                  ),
                ),
              ],
            ),
      centerTitle: true,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    _computeAdaptiveHeight(
      isNarrow: _isLikelyNarrowScreen,
      textScaleFactor:
          WidgetsBinding.instance.platformDispatcher.textScaleFactor,
    ),
  );
}

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/main_device_screen.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/widgets/device_preview_tile.dart';

final class _BlePlatform extends FlutterBluePlusPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlusPlatform.instance = _BlePlatform();

  setUpAll(() async {
    // Use real font metrics for the responsive labels and optional captures.
    var folder = File(Platform.resolvedExecutable).parent;
    while (!File(
          '${folder.path}/material_fonts/roboto-regular.ttf',
        ).existsSync() &&
        folder.parent.path != folder.path) {
      folder = folder.parent;
    }
    final bytes = ByteData.sublistView(
      File(
        '${folder.path}/material_fonts/roboto-regular.ttf',
      ).readAsBytesSync(),
    );
    for (final family in ['Ahem', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${folder.path}/material_fonts/materialicons-regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(568, 320),
    const Size(667, 375),
    const Size(844, 390),
    const Size(1024, 768),
    const Size(1200, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final withUpdate in [false, true]) {
        testWidgets(
          'dashboard fits $size at text scale $scale, update $withUpdate',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            tester.view.padding = const FakeViewPadding(
              left: 12,
              right: 12,
              bottom: 20,
            );
            addTearDown(tester.view.reset);
            final device = BluetoothDevice.fromId(
              withUpdate ? 'layout-test' : 'SmartSpin2k Demo',
            );
            final data = DeviceDataManager.forDevice(device)..setupDemoData();
            addTearDown(() {
              data.dispose();
              DeviceDataManager.clearDataForDevice(device);
            });
            final boundaryKey = GlobalKey();
            await http.runWithClient(
              () => tester.pumpWidget(
                RepaintBoundary(
                  key: boundaryKey,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: MainDeviceScreen(device: device),
                  ),
                ),
              ),
              () => MockClient(
                (_) async => http.Response('''[
          {"tag_name":"99.0.0","assets":[
            {"name":"SmartSpin2kFirmware-99.0.0.bin.zip",
             "browser_download_url":"https://example.com/firmware.zip"}
          ]}
        ]''', 200),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (withUpdate) {
              expect(find.byTooltip('Dismiss firmware update'), findsOneWidget);
            }

            void expectWithinScreen(Finder finder) {
              final rect = tester.getRect(finder);
              expect(rect.left, greaterThanOrEqualTo(12));
              expect(rect.right, lessThanOrEqualTo(size.width - 12));
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(size.height - 20));
            }

            final tiles = find.byType(DevicePreviewTile);
            expect(tiles, findsNWidgets(4));
            for (var index = 0; index < 4; index++) {
              expectWithinScreen(tiles.at(index));
              expect(tiles.at(index).hitTestable(), findsOneWidget);
              expect(
                tester.getSize(tiles.at(index)).height,
                greaterThanOrEqualTo(48),
              );
            }
            expectWithinScreen(find.text('Maintenance'));
            expectWithinScreen(find.textContaining('App Version:'));
            for (final scrollable in tester.stateList<ScrollableState>(
              find.byType(Scrollable),
            )) {
              expect(scrollable.position.maxScrollExtent, 0);
            }

            if (const bool.fromEnvironment('DEVICE_LAYOUT_SCREENSHOTS') &&
                scale == 1 &&
                !withUpdate) {
              await tester.runAsync(() async {
                final boundary =
                    boundaryKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  'build/device-layout-${size.width.toInt()}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            await tester.tap(find.text('Maintenance'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final title in [
              'Calibrate Trainer',
              'Update Firmware',
              'View Logs',
            ]) {
              expect(find.text(title).hitTestable(), findsOneWidget);
              expectWithinScreen(find.text(title));
            }
            for (var index = 0; index < 4; index++) {
              expectWithinScreen(tiles.at(index));
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}

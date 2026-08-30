import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/power_table_painter.dart';
import 'package:ss2kconfigapp/widgets/power_table_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('animation ticks keep the static power-table layer cached', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final deviceData = DeviceData()..isSimulated = true;
    deviceData.powerTableData[0][1] = 25;
    final device = BluetoothDevice.fromId('00:00:00:00:00:C1');

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 400,
          child: PowerTableChart(
            device: device,
            deviceData: deviceData,
            pollTargetPosition: false,
            initialDataLoadDelay: const Duration(days: 1),
          ),
        ),
      ),
    );
    // Let the asynchronous axis preference load finish before comparing
    // painter identities.
    await tester.pump();
    await tester.pump();

    List<CustomPainter> chartPainters() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(PowerTableChart),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<CustomPainter>()
        .toList();

    PowerTablePainter staticPainter() =>
        chartPainters().whereType<PowerTablePainter>().single;

    expect(chartPainters(), [
      isA<PowerTableOverlayPainter>(),
      isA<PowerTablePainter>(),
      isA<PowerTableOverlayPainter>(),
    ]);

    final painterBeforeTick = staticPainter();
    final tableBeforeTick = painterBeforeTick.powerTableData;

    await tester.pump(const Duration(milliseconds: 16));

    final painterAfterTick = staticPainter();
    expect(painterAfterTick, same(painterBeforeTick));
    expect(painterAfterTick.powerTableData, same(tableBeforeTick));

    await tester.pumpWidget(const SizedBox.shrink());
    deviceData.dispose();
  });
}

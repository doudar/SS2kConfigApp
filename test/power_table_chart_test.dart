import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/power_table_painter.dart';
import 'package:ss2kconfigapp/widgets/power_table_chart.dart';
import 'package:ss2kconfigapp/utils/constants.dart';

class _RecordingData extends DeviceData {
  final rows = <int>[];
  @override
  bool get isTransportActive => true;
  @override
  Future<void> requestSetting(
    BluetoothDevice device,
    String name, {
    int? extraByte,
  }) async {
    if (name == powerTableDataVname) rows.add(extraByte!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved axes and toggles notify their parent and persist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'power_table_swap_axes': true});
    final data = DeviceData()..isSimulated = true;
    final key = GlobalKey<PowerTableChartState>();
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PowerTableChart(
          key: key,
          device: BluetoothDevice.fromId('axes-test'),
          deviceData: data,
          pollTargetPosition: false,
          onAxisOrientationChanged: changes.add,
        ),
      ),
    );
    await tester.pump();
    expect(key.currentState!.swapAxes, isTrue);
    expect(changes, [true]);
    await key.currentState!.toggleAxisOrientation();
    await tester.pump();
    expect(key.currentState!.swapAxes, isFalse);
    expect(changes, [true, false]);
    expect(
      (await SharedPreferences.getInstance()).getBool('power_table_swap_axes'),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    data.dispose();
  });

  testWidgets('concurrent table refreshes share one paced read pass', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final data = _RecordingData();
    final key = GlobalKey<PowerTableChartState>();
    await tester.pumpWidget(
      MaterialApp(
        home: PowerTableChart(
          key: key,
          device: BluetoothDevice.fromId('read-test'),
          deviceData: data,
          pollTargetPosition: false,
          initialDataLoadDelay: const Duration(days: 1),
        ),
      ),
    );
    final first = key.currentState!.requestAllCadenceLines();
    await key.currentState!.requestAllCadenceLines();
    for (var i = 0; i < 11; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await first;
    expect(data.rows, List.generate(10, (i) => i));
    await tester.pumpWidget(const SizedBox.shrink());
    data.dispose();
  });

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

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/widgets/ss2k_app_bar.dart';

void main() {
  testWidgets('can suppress the implied back arrow during a critical action', (
    tester,
  ) async {
    final device = BluetoothDevice.fromId('00:11:22:33:44:55');

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/firmware',
        routes: {
          '/': (_) => const Scaffold(body: Text('Previous screen')),
          '/firmware': (_) => Scaffold(
            appBar: SS2KAppBar(
              device: device,
              title: 'Firmware Update',
              showDeviceHeader: false,
              backNavigationEnabled: false,
            ),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Firmware Update'), findsOneWidget);
  });
}

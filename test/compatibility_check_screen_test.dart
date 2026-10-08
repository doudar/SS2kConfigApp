import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/compatibility_check_screen.dart';
import 'package:ss2kconfigapp/screens/onboarding/onboarding_wizard.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/utils/ble_sensor_services.dart';
import 'package:ss2kconfigapp/utils/compatibility/compatibility_checker.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_session.dart';

import 'support/fake_ble_platform.dart';

List<int> le16(int v) => [v & 0xff, (v >> 8) & 0xff];

/// Records when it is run and disposed, and can hold its disposal open.
class RecordingChecker extends CompatibilityChecker {
  RecordingChecker(super.device, this.name, this.events, this.disposeGate);

  final String name;
  final List<String> events;
  final Completer<void>? disposeGate;

  @override
  Future<void> run() async => events.add('run $name');

  @override
  Future<void> dispose() async {
    events.add('dispose start $name');
    await disposeGate?.future;
    events.add('dispose end $name');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;

  setUp(() {
    platform.reset();
    platform.modelDisconnect = true;
    SharedPreferences.setMockInitialValues({});
  });

  // Tall enough that scan results and secondary actions are built without
  // scrolling.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsOneWidget);
  }

  Future<void> tearDownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Let the scan timeout and checker release run out.
    await tester.pump(const Duration(seconds: 20));
  }

  // Both device flows share one test: flutter_blue_plus keeps process-wide
  // operation locks, and cleanup still running when one fake-async test ends
  // can keep them held into the next. This also covers "Test a different
  // device".
  testWidgets('a cadence-only device fails, then a smart bike passes', (
    tester,
  ) async {
    useTallScreen(tester);
    final meter = DeviceIdentifier('00:00:00:00:03:03');
    final bike = DeviceIdentifier('00:00:00:00:03:01');
    platform.discoveredServices = [
      FakeGattService(ftmsServiceUUID, [
        FakeGattCharacteristic(ftmsIndoorBikeDataUUID),
      ]),
    ];

    await tester.pumpWidget(
      const MaterialApp(home: CompatibilityCheckScreen()),
    );
    await tester.tap(find.text('Find my bike'));
    await tester.pump();

    platform.emitScanResult(
      meter,
      name: 'Bike X',
      serviceUuids: [bleFitnessMachineServiceUuid],
    );
    // A heart-rate strap is not a power source and is not offered.
    platform.emitScanResult(
      DeviceIdentifier('00:00:00:00:03:02'),
      name: 'HRM',
      serviceUuids: [bleHeartRateServiceUuid],
    );
    await pumpUntil(tester, find.text('Bike X'));
    expect(find.text('Smart bike (FTMS)'), findsOneWidget);
    expect(find.text('HRM'), findsNothing);

    await tester.tap(find.text('Bike X'));
    await pumpUntil(tester, find.text('Connected. Start pedaling!'));

    platform.emitNotification(meter, ftmsIndoorBikeDataUUID, [
      ...le16(1 << 2),
      ...le16(0),
      ...le16(180),
    ], serviceUuid: ftmsServiceUUID);
    await tester.pump();
    await tester.pump(const Duration(minutes: 3, seconds: 1));

    expect(find.text("Bike X isn't compatible"), findsOneWidget);
    expect(find.textContaining('cadence but no power'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    await tester.tap(find.text('Test a different device'));
    await tester.pump();
    platform.emitScanResult(
      bike,
      name: 'IC Bike',
      serviceUuids: [bleFitnessMachineServiceUuid],
    );
    await pumpUntil(tester, find.text('IC Bike'));
    await tester.tap(find.text('IC Bike'));
    await pumpUntil(tester, find.text('Connected. Start pedaling!'));

    platform.emitNotification(bike, ftmsIndoorBikeDataUUID, [
      ...le16((1 << 2) | (1 << 6)),
      ...le16(2000),
      ...le16(180),
      ...le16(200),
    ], serviceUuid: ftmsServiceUUID);
    await pumpUntil(tester, find.text('IC Bike works with SmartSpin2k'));
    expect(find.text('Get a SmartSpin2k'), findsOneWidget);
    expect(find.text('Check bike fit'), findsOneWidget);

    await tearDownTree(tester);
  });

  group('restarting a check waits for the old checker to be disposed', () {
    final events = <String>[];
    final gates = <String, Completer<void>>{};
    final created = <String, int>{};
    final checkers = <RecordingChecker>[];

    CompatibilityChecker makeChecker(BluetoothDevice device) {
      final id = device.remoteId.str;
      final n = created[id] = (created[id] ?? 0) + 1;
      final name = '$id#$n';
      final checker = RecordingChecker(device, name, events, gates[name]);
      checkers.add(checker);
      return checker;
    }

    setUp(() {
      events.clear();
      gates.clear();
      created.clear();
      checkers.clear();
    });

    Future<void> openWithCandidates(
      WidgetTester tester,
      List<(DeviceIdentifier, String)> candidates,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: CompatibilityCheckScreen(checkerFactory: makeChecker),
        ),
      );
      await tester.tap(find.text('Find my bike'));
      await tester.pump();
      for (final (id, name) in candidates) {
        platform.emitScanResult(
          id,
          name: name,
          serviceUuids: [bleFitnessMachineServiceUuid],
        );
      }
      await pumpUntil(tester, find.text(candidates.last.$2));
    }

    testWidgets('Cancel, then testing another device', (tester) async {
      final a = DeviceIdentifier('00:00:00:00:06:01');
      final b = DeviceIdentifier('00:00:00:00:06:02');
      gates['${a.str}#1'] = Completer<void>();
      await openWithCandidates(tester, [(a, 'Bike A'), (b, 'Bike B')]);

      await tester.tap(find.text('Bike A'));
      await tester.pump();
      await tester.pump();
      expect(events, ['run ${a.str}#1']);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      platform.emitScanResult(
        b,
        name: 'Bike B',
        serviceUuids: [bleFitnessMachineServiceUuid],
      );
      await pumpUntil(tester, find.text('Bike B'));
      await tester.tap(find.text('Bike B'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(events, ['run ${a.str}#1', 'dispose start ${a.str}#1']);

      gates['${a.str}#1']!.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(events, [
        'run ${a.str}#1',
        'dispose start ${a.str}#1',
        'dispose end ${a.str}#1',
        'run ${b.str}#1',
      ]);

      await tearDownTree(tester);
    });

    testWidgets('Try again on the same device', (tester) async {
      final a = DeviceIdentifier('00:00:00:00:06:03');
      gates['${a.str}#1'] = Completer<void>();
      await openWithCandidates(tester, [(a, 'Bike A')]);

      await tester.tap(find.text('Bike A'));
      await tester.pump();
      await tester.pump();
      expect(events, ['run ${a.str}#1']);

      // Fail the first check so the result view offers "Try again".
      checkers.first.state.value = const CompatibilityCheckState(
        stage: CompatibilityStage.failed,
        failure: CompatibilityFailure.connectionFailed,
      );
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(events, ['run ${a.str}#1', 'dispose start ${a.str}#1']);

      gates['${a.str}#1']!.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(events.last, 'run ${a.str}#2');
      expect(
        events.indexOf('dispose end ${a.str}#1'),
        lessThan(events.indexOf('run ${a.str}#2')),
      );

      await tearDownTree(tester);
    });
  });

  testWidgets('the scan screen links to the check below Guided Setup', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: ScanScreen()));
    await tester.tap(find.text('Is my bike compatible?'));
    await tester.pumpAndSettle();
    expect(find.byType(CompatibilityCheckScreen), findsOneWidget);

    await tearDownTree(tester);
  });

  testWidgets('the welcome step opens the check without ending onboarding', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => WizardSession(),
          child: const OnboardingWizard(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text("Don't have a SmartSpin2k yet? Check your bike"),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CompatibilityCheckScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text("Let's set up your SmartSpin2k"), findsOneWidget);
    expect(await OnboardingState.isCompleted(), isFalse);

    await tearDownTree(tester);
  });
}

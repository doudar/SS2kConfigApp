import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/onboarding/onboarding_wizard.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_session.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';
import 'package:ss2kconfigapp/widgets/smartspin_introduction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OnboardingState.completedNotifier.value = false;
  });

  testWidgets('real opening screens fit phones, landscape and large text', (
    tester,
  ) async {
    final screenshots = const bool.fromEnvironment('INTRO_SCREENSHOTS');
    await tester.runAsync(() async {
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
      for (final family in ['Ahem', 'Roboto', 'Segoe UI']) {
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
    final theme = ThemeProvider();
    await tester.pump();
    addTearDown(() {
      theme.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final size in [
      const Size(390, 844),
      const Size(1280, 800),
      const Size(1920, 1080),
      const Size(320, 568),
      const Size(844, 390),
    ]) {
      for (final scale in [1.0, 2.0]) {
        for (final welcome in [true, false]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          final boundary = GlobalKey();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: welcome
                    ? ChangeNotifierProvider(
                        create: (_) => WizardSession(),
                        child: const OnboardingWizard(),
                      )
                    : const ScanScreen(),
              ),
            ),
          );
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/ss2kv3.png'),
              boundary.currentContext!,
            );
          });
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$size, text $scale, welcome $welcome',
          );
          expect(find.byType(SmartSpinIntroduction), findsOneWidget);
          final action = find.text(welcome ? 'Set up my hardware' : 'SCAN');
          expect(action.hitTestable(), findsOneWidget);

          if (screenshots && scale == 1 && size.width >= 390) {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await render.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/intro-${welcome ? 'welcome' : 'scan'}-${size.width.toInt()}.png',
              );
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.ensureVisible(find.text('Hardware required'));
          await tester.pumpAndSettle();
          expect(find.text('Hardware required').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets(
    'setup still advances to bike selection; exit returns to discovery',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: const ScanScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guided Setup'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingWizard), findsOneWidget);
      await tester.tap(find.text('Set up my hardware'));
      await tester.pumpAndSettle();
      expect(find.text('Select Your Bike'), findsOneWidget);
      await tester.tap(find.text('Exit Setup'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingWizard), findsNothing);
      expect(find.byType(ScanScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hardware explanation supports a light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: SmartSpinIntroduction()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Hardware required'), findsOneWidget);
  });
}

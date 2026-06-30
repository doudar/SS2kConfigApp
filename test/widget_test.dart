import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/screens/onboarding/onboarding_wizard.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_session.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';

// ---------------------------------------------------------------------------
// Routing harness: mirrors _SmartSpin2kAppState.buildHomeScreen() so that
// regressions in the routing logic are caught without touching BLE/AppLinks.
// Any change to the routing logic in main.dart must be reflected here.
// ---------------------------------------------------------------------------

class _RoutingHarness extends StatelessWidget {
  final bool onboardingCompleted;
  final bool demoMode;

  const _RoutingHarness({
    required this.onboardingCompleted,
    this.demoMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (onboardingCompleted || demoMode) {
      return const ScanScreen();
    }
    return ChangeNotifierProvider(
      create: (_) => WizardSession(),
      child: const OnboardingWizard(),
    );
  }
}

Widget _wrap(Widget child) => ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(home: child),
    );

// ---------------------------------------------------------------------------
// Reactive harness: mirrors the _SmartSpin2kAppState listener wiring so the
// T024/T026 fix (completedNotifier → rebuild to ScanScreen) is exercised.
// ---------------------------------------------------------------------------

class _ReactiveHarness extends StatefulWidget {
  const _ReactiveHarness();

  @override
  State<_ReactiveHarness> createState() => _ReactiveHarnessState();
}

class _ReactiveHarnessState extends State<_ReactiveHarness> {
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    OnboardingState.completedNotifier.addListener(_onCompleted);
    OnboardingState.isCompleted().then((v) {
      if (mounted) setState(() => _completed = v);
    });
  }

  void _onCompleted() {
    if (OnboardingState.completedNotifier.value && mounted) {
      setState(() => _completed = true);
    }
  }

  @override
  void dispose() {
    OnboardingState.completedNotifier.removeListener(_onCompleted);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) return const ScanScreen();
    return ChangeNotifierProvider(
      create: (_) => WizardSession(),
      child: const OnboardingWizard(),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OnboardingState.completedNotifier.value = false;
  });

  group('Routing seam', () {
    testWidgets('Shows ScanScreen when onboarding completed', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      await tester.pumpWidget(_wrap(const _RoutingHarness(onboardingCompleted: true)));
      await tester.pumpAndSettle();
      expect(find.byType(ScanScreen), findsOneWidget);
      expect(find.byType(OnboardingWizard), findsNothing);
    });

    testWidgets('Shows OnboardingWizard when onboarding not completed', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_wrap(const _RoutingHarness(onboardingCompleted: false)));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingWizard), findsOneWidget);
      expect(find.byType(ScanScreen), findsNothing);
    });

    testWidgets('Shows ScanScreen in demo mode regardless of onboarding flag', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        _wrap(const _RoutingHarness(onboardingCompleted: false, demoMode: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ScanScreen), findsOneWidget);
      expect(find.byType(OnboardingWizard), findsNothing);
    });
  });

  group('Reactive rebuild (T024/T026)', () {
    testWidgets('Rebuilds to ScanScreen when markCompleted fires mid-session', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        _wrap(const _ReactiveHarness()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingWizard), findsOneWidget);

      await OnboardingState.markCompleted();
      await tester.pumpAndSettle();

      expect(find.byType(ScanScreen), findsOneWidget);
      expect(find.byType(OnboardingWizard), findsNothing);
    });
  });
}

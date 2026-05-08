import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/screens/onboarding/onboarding_wizard.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_session.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';

/// Minimal harness that mirrors the onboarding routing in SmartSpin2kApp.build()
/// without touching BLE. Reads SharedPreferences via OnboardingState, then
/// shows ScanScreen (completed) or OnboardingWizard (not completed).
class _RoutingHarness extends StatefulWidget {
  const _RoutingHarness();

  @override
  State<_RoutingHarness> createState() => _RoutingHarnessState();
}

class _RoutingHarnessState extends State<_RoutingHarness> {
  bool _completed = true;
  final WizardSession _session = WizardSession();

  @override
  void initState() {
    super.initState();
    OnboardingState.isCompleted().then((v) {
      if (mounted) setState(() => _completed = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) return const ScanScreen();
    return ChangeNotifierProvider<WizardSession>.value(
      value: _session,
      child: const OnboardingWizard(),
    );
  }
}

Widget _wrap() => ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MaterialApp(home: _RoutingHarness()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Shows ScanScreen when onboarding_completed is true', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(find.byType(ScanScreen), findsOneWidget);
    expect(find.byType(OnboardingWizard), findsNothing);
  });

  testWidgets('Shows OnboardingWizard when onboarding_completed is false', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingWizard), findsOneWidget);
    expect(find.byType(ScanScreen), findsNothing);
  });
}

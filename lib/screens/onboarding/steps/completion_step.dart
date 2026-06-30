import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/onboarding_state.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../workout_screen.dart';
import '../../scan_screen.dart';
import '../../main_device_screen.dart';
import 'connect_training_app_step.dart';

class CompletionStep extends StatefulWidget {
  const CompletionStep({Key? key}) : super(key: key);

  @override
  State<CompletionStep> createState() => _CompletionStepState();
}

class _CompletionStepState extends State<CompletionStep> {
  @override
  void dispose() {
    // Fire after navigation, not on entry — calling markCompleted() in initState
    // triggers completedNotifier synchronously, which causes main.dart to rebuild
    // home to ScanScreen and removes this screen before the user can act on it.
    OnboardingState.markCompleted();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text(
                "You're all set!",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                "Your SmartSpin2k is configured and ready. Take 30 seconds to read your personalized first-ride routine — "
                "it's the same checklist every ride, so you'll have it down by tomorrow.",
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Your First Ride Guide'),
                  onPressed: () {
                    final session = context.read<WizardSession>();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ConnectTrainingAppStep(
                        bikeType: session.bikeType,
                        dataSource: session.dataSourceChoice,
                        sideSwitchMode: session.sideSwitchMode,
                      ),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Or jump straight to:',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Go to Device Settings'),
                  onPressed: () {
                    final device = context.read<WizardSession>().connectedDevice;
                    final navigator = Navigator.of(context);

                    if (navigator.canPop()) {
                      navigator.popUntil((route) => route.isFirst);
                    } else {
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                        (route) => false,
                      );
                    }

                    if (device != null) {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => MainDeviceScreen(device: device),
                          settings: const RouteSettings(name: '/MainDeviceScreen'),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.fitness_center),
                  label: const Text('Start a Guided Workout'),
                  onPressed: () {
                    final device = context.read<WizardSession>().connectedDevice;
                    final navigator = Navigator.of(context);

                    if (navigator.canPop()) {
                      // Returning user: ScanScreen is already the root route — pop
                      // back to it rather than creating a duplicate instance, which
                      // causes a GlobalKey conflict on ScaffoldMessengerState.
                      navigator.popUntil((route) => route.isFirst);
                    } else {
                      // New user: wizard was the initial route, replace with ScanScreen.
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                        (route) => false,
                      );
                    }

                    if (device != null) {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => MainDeviceScreen(device: device),
                          settings: const RouteSettings(name: '/MainDeviceScreen'),
                        ),
                      );
                      navigator.push(MaterialPageRoute(builder: (_) => WorkoutScreen(device: device)));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

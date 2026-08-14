/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app_links/app_links.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/strava_service.dart';
import 'services/intervals_service.dart';
import 'screens/bluetooth_off_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/onboarding/onboarding_wizard.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'utils/onboarding/onboarding_state.dart';
import 'utils/onboarding/wizard_session.dart';
import 'utils/theme_provider.dart';
import 'utils/demo.dart' show demoModeBypass;
import 'utils/app_release_service.dart';

void main() async {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith(
    options: {
      'platforms': ['windows', 'macos', 'linux'],
    },
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SmartSpin2kApp(),
    ),
  );
}

//
// This widget shows BluetoothOffScreen or
// ScanScreen depending on the adapter state
//
class SmartSpin2kApp extends StatefulWidget {
  const SmartSpin2kApp({Key? key}) : super(key: key);

  @override
  State<SmartSpin2kApp> createState() => _SmartSpin2kAppState();
}

class _SmartSpin2kAppState extends State<SmartSpin2kApp> {
  static const String _dismissedAppReleaseKey = 'dismissed_app_release';
  static const MethodChannel _powerChannel = MethodChannel(
    'com.example.ss2kconfigapp/power',
  );
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;
  // Start false on native so a clean install shows the wizard, not a ScanScreen flash.
  // kIsWeb stays true because the wizard is never shown on web.
  bool _onboardingCompleted = kIsWeb;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      try {
        _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((
          state,
        ) {
          _adapterState = state;
          if (mounted) {
            setState(() {});
          }
        });
      } catch (e) {
        debugPrint('Error listening to adapter state: $e');
        _adapterState = BluetoothAdapterState.on;
      }
    } else {
      _adapterState = BluetoothAdapterState.on;
    }
    _initDeepLinkHandling();
    _requestBatteryOptimizationExemption();
    _checkOnboardingState();
    // React to markCompleted() fired mid-session (e.g. CompletionStep).
    OnboardingState.completedNotifier.addListener(_onCompletedNotifierChanged);
    // React to demo-mode tap-target activated from ScanScreen or WelcomeStep.
    demoModeBypass.addListener(_onDemoModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForAppUpdate());
    });
  }

  Future<void> _checkForAppUpdate() async {
    if (kIsWeb) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final release = await const AppReleaseService().fetchLatest();
      if (!mounted || release == null) return;

      final installedVersion =
          '${packageInfo.version}+${packageInfo.buildNumber}';
      if (!isAppVersionNewer(release.version, installedVersion)) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_dismissedAppReleaseKey) == release.version) return;

      final destination = appUpdateDestination(
        platform: defaultTargetPlatform,
        installerStore: packageInfo.installerStore,
        release: release,
      );
      if (!mounted) return;
      _showAppUpdateBanner(
        release: release,
        installedVersion: installedVersion,
        destination: destination,
      );
    } catch (error) {
      debugPrint('Unable to check for an app update: $error');
    }
  }

  void _showAppUpdateBanner({
    required AppRelease release,
    required String installedVersion,
    required Uri destination,
  }) {
    final messenger = _scaffoldKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update_alt),
        content: Text(
          'SmartSpin2k Companion ${release.version} is available. '
          'You have $installedVersion.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              messenger.hideCurrentMaterialBanner();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_dismissedAppReleaseKey, release.version);
            },
            child: const Text('NOT NOW'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              messenger.hideCurrentMaterialBanner();
              final launched = await launchUrl(
                destination,
                mode: LaunchMode.externalApplication,
              );
              if (!launched) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Unable to open the app update page.'),
                  ),
                );
              }
            },
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  void _onCompletedNotifierChanged() {
    if (OnboardingState.completedNotifier.value && mounted) {
      setState(() => _onboardingCompleted = true);
    }
  }

  void _onDemoModeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkOnboardingState() async {
    final completed = await OnboardingState.isCompleted();
    if (mounted) {
      setState(() => _onboardingCompleted = completed);
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final isIgnoringBatteryOptimizations =
          await _powerChannel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;

      if (!isIgnoringBatteryOptimizations) {
        await _powerChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      }
    } catch (e) {
      debugPrint('Unable to request battery optimization exemption: $e');
    }
  }

  Future<void> _initDeepLinkHandling() async {
    _appLinks = AppLinks();

    // Handle initial URI if the app was launched with one
    final uri = await _appLinks.getInitialLink();
    if (uri != null) {
      _handleDeepLink(uri);
    }

    // Handle URI when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Deep link error: $err');
      },
    );
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Handling deep link: ${uri.toString()}');
    debugPrint('URI scheme: ${uri.scheme}, host: ${uri.host}');

    // Handle Strava OAuth callback
    if (uri.scheme == 'smartspin2k' &&
        (uri.host == 'redirect' || uri.host == 'localhost')) {
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];
      // final state = uri.queryParameters['state']; // Unused

      if (error != null) {
        debugPrint('Strava auth error: $error');
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Strava authentication error: $error'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (code != null) {
        debugPrint('Received auth code: $code');

        // Show loading dialog
        showDialog(
          context: _navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Connecting to Strava...'),
              ],
            ),
          ),
        );

        StravaService.handleAuthCallback(code).then((success) {
          debugPrint('Auth callback result: $success');

          // Close loading dialog
          Navigator.of(_navigatorKey.currentContext!).pop();

          if (success && mounted) {
            _scaffoldKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('Successfully connected to Strava'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );

            // Ensure we're showing the main screen when returning from auth
            while (_navigatorKey.currentState?.canPop() ?? false) {
              _navigatorKey.currentState?.pop();
            }
            // Rebuild the screen to ensure proper state
            if (mounted) {
              setState(() {});
            }
          } else if (mounted) {
            _scaffoldKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('Failed to connect to Strava'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      }
      return; // handled
    }

    // Handle Intervals.icu OAuth callback
    if (uri.scheme == 'smartspin2k' && uri.host == 'intervals_redirect') {
      debugPrint('Handling Intervals.icu callback');
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        debugPrint('Intervals.icu auth error: $error');
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Intervals.icu authentication error: $error'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (code != null) {
        debugPrint('Received Intervals.icu auth code: $code');

        // Show loading dialog
        showDialog(
          context: _navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Connecting to Intervals.icu...'),
              ],
            ),
          ),
        );

        IntervalsService.handleAuthCallback(code).then((success) {
          debugPrint('Intervals.icu auth callback result: $success');

          // Close loading dialog
          Navigator.of(_navigatorKey.currentContext!).pop();

          if (success && mounted) {
            _scaffoldKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('Successfully connected to Intervals.icu'),
                backgroundColor: Color(0xFF1B4F72),
                duration: Duration(seconds: 3),
              ),
            );

            // Ensure we're showing the main screen when returning from auth
            while (_navigatorKey.currentState?.canPop() ?? false) {
              _navigatorKey.currentState?.pop();
            }
            // Rebuild the screen to ensure proper state
            if (mounted) {
              setState(() {});
            }
          } else if (mounted) {
            _scaffoldKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('Failed to connect to Intervals.icu'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      }
      return; // handled
    }

    // Add a catch-all debug log for any truly unhandled deep links
    debugPrint(
      'Unhandled deep link: ${uri.toString()} (scheme: ${uri.scheme}, host: ${uri.host})',
    );
  }

  @override
  void dispose() {
    _adapterStateStateSubscription.cancel();
    _linkSubscription?.cancel();
    OnboardingState.completedNotifier.removeListener(
      _onCompletedNotifierChanged,
    );
    demoModeBypass.removeListener(_onDemoModeChanged);
    super.dispose();
  }

  @visibleForTesting
  Widget buildHomeScreen({
    required BluetoothAdapterState adapterState,
    required bool onboardingCompleted,
    required bool demoMode,
  }) {
    if (adapterState != BluetoothAdapterState.on && !kIsWeb) {
      return BluetoothOffScreen(adapterState: adapterState);
    } else if (onboardingCompleted || demoMode) {
      return const ScanScreen();
    } else {
      return ChangeNotifierProvider(
        create: (_) => WizardSession(),
        child: const OnboardingWizard(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = buildHomeScreen(
      adapterState: _adapterState,
      onboardingCompleted: _onboardingCompleted,
      demoMode: demoModeBypass.value,
    );

    final themeProvider = Provider.of<ThemeProvider>(context);
    return ScaffoldMessenger(
      key: _scaffoldKey,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        themeMode: themeProvider.themeMode,
        theme: themeProvider.lightTheme,
        darkTheme: themeProvider.darkTheme,
        home: screen,
        navigatorObservers: [BluetoothAdapterStateObserver()],
      ),
    );
  }
}

//
// This observer listens for Bluetooth Off and dismisses the DeviceScreen
//
class BluetoothAdapterStateObserver extends NavigatorObserver {
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == '/MainDeviceScreen') {
      // Start listening to Bluetooth state changes when a new route is pushed
      if (!kIsWeb) {
        try {
          _adapterStateSubscription ??= FlutterBluePlus.adapterState.listen((
            state,
          ) {
            if (state != BluetoothAdapterState.on) {
              // Pop the current route if Bluetooth is off
              navigator?.pop();
            }
          });
        } catch (e) {
          debugPrint('Error listening to adapter state in observer: $e');
        }
      }
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    // Cancel the subscription when the route is popped
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/main.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';
import 'package:ss2kconfigapp/utils/workout/workout_connected_accounts.dart';

import 'support/fake_ble_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlusPlatform.instance = FakeBlePlatform();

  for (final (host, provider) in [
    ('redirect', 'Strava'),
    ('intervals_redirect', 'Intervals.icu'),
  ]) {
    testWidgets('$provider sign-in preserves the ride and account dialog', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});
      late MockStreamHandlerEventSink links;
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('com.llfbandit.app_links/events'),
        MockStreamHandler.inline(
          onListen: (_, sink) {
            links = sink;
          },
        ),
      );
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => ThemeProvider(),
              child: const SmartSpin2kApp(),
            ),
          );
          await tester.pumpAndSettle();
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          final ride = MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Current ride')),
          );
          unawaited(navigator.push(ride));
          await tester.pumpAndSettle();
          WorkoutConnectedAccounts.showConnectedAccountsDialog(
            tester.element(find.text('Current ride')),
          );
          await tester.pumpAndSettle();
          links.success('smartspin2k://$host?code=test-code');
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.text('Connected · Tap to disconnect'), findsOneWidget);
          expect(ride.isActive, isTrue);
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(ride.isCurrent, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (_) async => http.Response(
            '{"access_token":"test","refresh_token":"test","expires_at":4000000000}',
            200,
          ),
        ),
      );
    });
  }
}

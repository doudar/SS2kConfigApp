import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/services/intervals_service.dart';
import 'package:ss2kconfigapp/services/strava_service.dart';
import 'package:ss2kconfigapp/utils/workout/workout_account_prompt.dart';

Widget app({
  Future<void> Function(BuildContext)? intervals,
  Future<void> Function(BuildContext)? strava,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: WorkoutAccountPrompt(
        connectIntervals: intervals ?? (_) async {},
        connectStrava: strava ?? (_) async {},
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'suggests only unconnected services and respects existing expired credentials',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Connect Intervals.icu'), findsOneWidget);
      expect(find.text('Connect Strava'), findsOneWidget);

      // A mobile callback can complete after the browser has already closed.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('strava_access_token', 'test-token');
      await prefs.setString('strava_expires_at', '0');
      StravaService.connectionChanges.value++;
      await tester.pumpAndSettle();
      expect(find.text('Connect Strava'), findsNothing);
      expect(find.text('Connect Intervals.icu'), findsOneWidget);

      await prefs.setString('intervals_access_token', 'test-token');
      IntervalsService.connectionChanges.value++;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workout-account-prompt')),
        findsNothing,
      );

      await StravaService.clearTokens();
      await tester.pumpAndSettle();
      expect(find.text('Connect Strava'), findsOneWidget);
      expect(find.text('Connect Intervals.icu'), findsNothing);
    },
  );

  testWidgets('dismissal persists across lobby visits', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss account suggestions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workout-account-prompt')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workout-account-prompt')), findsNothing);
  });

  testWidgets(
    'login routes correctly, prevents duplicate launches, and refreshes after success',
    (tester) async {
      final pending = Completer<void>();
      var intervals = 0;
      var strava = 0;
      await tester.pumpWidget(
        app(
          intervals: (_) async {
            intervals++;
            await pending.future;
          },
          strava: (_) async {
            strava++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect Intervals.icu'));
      await tester.pump();
      await tester.tap(find.text('Connect Intervals.icu'));
      expect(intervals, 1);
      expect(strava, 0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('intervals_access_token', 'test-token');
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Connect Intervals.icu'), findsNothing);
      await tester.tap(find.text('Connect Strava'));
      await tester.pumpAndSettle();
      expect(strava, 1);
      // Returning without tokens (for example, cancelling login) keeps the CTA.
      expect(find.text('Connect Strava'), findsOneWidget);
    },
  );

  testWidgets('connected accounts never flash a suggestion during loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'intervals_access_token': 'test-token',
      'strava_access_token': 'test-token',
    });
    await tester.pumpWidget(app());
    expect(find.byKey(const ValueKey('workout-account-prompt')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workout-account-prompt')), findsNothing);
  });

  testWidgets('suggestions fit small screens with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: WorkoutAccountPrompt(
                connectIntervals: (_) async {},
                connectStrava: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect Strava'));
    expect(find.text('Connect Strava').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

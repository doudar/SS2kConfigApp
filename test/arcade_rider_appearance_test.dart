import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_rider_appearance.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_rider_customizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all rider choices survive a storage reload alongside audio and mode',
    () async {
      SharedPreferences.setMockInitialValues({});
      const rider = ArcadeRiderAppearance(
        skin: Color(0xff794c36),
        hair: Color(0xffed87c0),
        jersey: Color(0xff67cfff),
        shorts: Color(0xff252b40),
        helmet: Color(0xfff1f5ff),
        bike: Color(0xffffaa58),
        shoes: Color(0xffff6259),
        hairStyle: ArcadeHairStyle.ponytail,
      );
      await ArcadePreferences.saveMode(true);
      await ArcadePreferences.saveMusic(true);
      await ArcadePreferences.saveRider(rider);
      final storage = await SharedPreferences.getInstance();
      await storage.reload();
      final restored = await ArcadePreferences.load();
      expect(restored.rider.toJson(), rider.toJson());
      expect(restored.arcadeMode, isTrue);
      expect(restored.musicEnabled, isTrue);
    },
  );

  test(
    'invalid appearance fields fall back without discarding valid choices',
    () {
      final rider = ArcadeRiderAppearance.fromJson({
        'skin': 'corrupt',
        'hairStyle': 'unknown',
        'jersey': 0xff67cfff,
        'helmet': -1,
        'shoes': null,
      });
      const defaults = ArcadeRiderAppearance();
      expect(rider.skin, defaults.skin);
      expect(rider.hairStyle, defaults.hairStyle);
      expect(rider.jersey, const Color(0xff67cfff));
      expect(rider.helmet, defaults.helmet);
      expect(rider.shoes, defaults.shoes);
    },
  );

  test(
    'corrupt rider storage preserves saved music and workout mode',
    () async {
      SharedPreferences.setMockInitialValues({
        'workout_arcade_mode': true,
        'workout_arcade_music': true,
        'workout_arcade_rider': '{invalid',
      });
      final restored = await ArcadePreferences.load();
      expect(restored.arcadeMode, isTrue);
      expect(restored.musicEnabled, isTrue);
      expect(restored.rider.toJson(), const ArcadeRiderAppearance().toJson());
    },
  );

  testWidgets(
    'editor previews changes; cancel keeps the original and apply returns the look',
    (tester) async {
      const original = ArcadeRiderAppearance();
      ArcadeRiderAppearance? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('EDIT'),
                onPressed: () async {
                  result = await showDialog<ArcadeRiderAppearance>(
                    context: context,
                    builder: (_) =>
                        const ArcadeRiderCustomizer(initial: original),
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (final apply in [false, true]) {
        await tester.tap(find.text('EDIT'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Deep brown'));
        await tester.tap(find.byTooltip('Deep brown'));
        await tester.ensureVisible(find.text('Ponytail'));
        await tester.tap(find.text('Ponytail'));
        await tester.tap(find.text(apply ? 'Apply look' : 'Cancel'));
        await tester.pumpAndSettle();
        if (apply) {
          expect(result?.skin, const Color(0xff794c36));
          expect(result?.hairStyle, ArcadeHairStyle.ponytail);
        } else {
          expect(result, isNull);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('editor remains scrollable on phones and short tablet windows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(320, 568), const Size(844, 330)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: ArcadeRiderCustomizer(initial: ArcadeRiderAppearance()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Shoes & gloves'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Apply look'), findsOneWidget);
    }
  });
}

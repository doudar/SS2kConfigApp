import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/widgets/stepper_travel_gauge.dart';

void main() {
  Widget host({double? progress, bool reducedMotion = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Center(child: StepperTravelGauge(progress: progress)),
      ),
    );
  }

  Color bezelColor(WidgetTester tester) {
    final bezel = tester.widget<DecoratedBox>(
      find.byKey(const Key('stepper_travel_gauge_bezel')),
    );
    final decoration = bezel.decoration as BoxDecoration;
    return (decoration.border! as Border).top.color;
  }

  testWidgets('shows a compact travel dial with a one-decimal percentage', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(progress: .523));

    expect(find.text('TRAVEL'), findsOneWidget);
    expect(find.text('52.3%'), findsOneWidget);
    expect(find.textContaining('steps'), findsNothing);
    expect(find.bySemanticsLabel('Stepper travel'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(StepperTravelGauge)).value,
      '52.3 percent of stepper travel',
    );
    expect(
      tester.getSize(find.byKey(const Key('stepper_travel_gauge_dial'))),
      const Size(100, 100),
    );

    semantics.dispose();
  });

  testWidgets('unknown travel stays neutral without a fabricated needle', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host());

    expect(find.text('TRAVEL'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('steps'), findsNothing);
    expect(
      tester.getSemantics(find.byType(StepperTravelGauge)).value,
      'Unavailable',
    );
    expect(
      tester
          .widget<CustomPaint>(
            find.byKey(const Key('stepper_travel_gauge_dial')),
          )
          .painter,
      isNotNull,
    );
    semantics.dispose();
  });

  testWidgets('turns the bezel red near full travel', (tester) async {
    await tester.pumpWidget(host(progress: .5));
    final normal = bezelColor(tester);

    await tester.pumpWidget(host(progress: .95));
    final nearLimit = bezelColor(tester);

    expect(nearLimit, const Color(0xffff6b6b));
    expect(nearLimit, isNot(normal));
  });

  testWidgets('smoothly animates a known needle and honors reduced motion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(progress: .2));
    await tester.pumpWidget(host(progress: .8));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);

    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byType(StepperTravelGauge)).value,
      '80.0 percent of stepper travel',
    );

    await tester.pumpWidget(host(progress: .2, reducedMotion: true));
    await tester.pumpWidget(host(progress: .8, reducedMotion: true));
    await tester.pump();
    expect(
      tester.getSemantics(find.byType(StepperTravelGauge)).value,
      '80.0 percent of stepper travel',
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    semantics.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/widgets/shifter_gear_indicator.dart';

void main() {
  Widget host({
    required String value,
    bool shifting = false,
    bool reducedMotion = false,
    double textScale = 1,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Center(
          child: ShifterGearIndicator(
            value: value,
            shifting: shifting,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  testWidgets('exposes one accessible current gear value', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(value: '7'));

    expect(find.bySemanticsLabel('Virtual gear'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('rolls from the previous gear to the new gear', (tester) async {
    await tester.pumpWidget(host(value: '7'));
    await tester.pumpWidget(host(value: '8'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('7'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('7'), findsNothing);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('reduced motion switches values without a rolling transition', (
    tester,
  ) async {
    await tester.pumpWidget(host(value: '7', reducedMotion: true));
    await tester.pumpWidget(host(value: '8', reducedMotion: true));
    await tester.pump();

    expect(find.text('7'), findsNothing);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('pending shifts add a subtle finite visual effect', (
    tester,
  ) async {
    await tester.pumpWidget(host(value: '7', shifting: true));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);

    await tester.pumpWidget(host(value: '7'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('applies large text scaling once and reserves matching space', (
    tester,
  ) async {
    await tester.pumpWidget(host(value: '7'));
    final normalTextHeight = tester.getSize(find.text('7')).height;

    await tester.pumpWidget(host(value: '7', textScale: 2));
    final largeTextHeight = tester.getSize(find.text('7')).height;
    final indicatorHeight = tester
        .getSize(find.byType(ShifterGearIndicator))
        .height;

    expect(largeTextHeight, closeTo(normalTextHeight * 2, .1));
    expect(indicatorHeight, closeTo(largeTextHeight, .1));
  });
}

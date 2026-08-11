import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/widgets/homing_proximity_gauge.dart';

void main() {
  testWidgets('shows current, target, and accessible proximity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomingProximityGauge(
            progress: 0.5,
            title: 'Motor Load',
            currentLabel: 'Min',
            targetLabel: 'Max',
            detailLabel: '',
          ),
        ),
      ),
    );

    expect(find.text('Motor Load'), findsOneWidget);
    expect(find.text('Min'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.textContaining('SG falls'), findsNothing);
    final containerFinder = find.byKey(
      const Key('homing_proximity_gauge_container'),
    );
    final container = tester.widget<Container>(containerFinder);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(decoration.border!.top.width, 1);
    expect(
      decoration.border!.top.color,
      Theme.of(tester.element(containerFinder)).colorScheme.error,
    );
    expect(
      find.bySemanticsLabel('Motor Load. Min. Max. 50 percent to target.'),
      findsOneWidget,
    );
  });
}

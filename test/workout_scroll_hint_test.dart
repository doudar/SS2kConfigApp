import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/widgets/workout_dialog.dart';

void main() {
  final hint = find.byIcon(Icons.keyboard_arrow_down_rounded);

  Future<void> open(
    WidgetTester tester,
    Widget content, {
    bool listBody = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutDialog(
            title: const Text('Workout settings'),
            listBody: listBody,
            content: content,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cue appears for clipped content and swipes pass through it', (
    tester,
  ) async {
    await open(tester, const SizedBox(height: 1200));
    expect(hint, findsOneWidget);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(tester.getCenter(hint).dx, closeTo(dialog.center.dx, 1));
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    await tester.dragFrom(tester.getCenter(hint), const Offset(0, -300));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, greaterThan(before));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(hint, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cue responds to content growth, shrinkage and window resizing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, const SizedBox(height: 50));
    expect(hint, findsNothing);
    await open(tester, const SizedBox(height: 650));
    expect(hint, findsOneWidget);
    tester.view.physicalSize = const Size(1000, 1200);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(hint, findsOneWidget);
    await open(tester, const SizedBox(height: 50));
    expect(hint, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library viewport has its own cue even when the dialog fits', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await open(
      tester,
      ListView.builder(
        controller: controller,
        itemCount: 30,
        itemExtent: 60,
        itemBuilder: (_, index) => Text('Workout $index'),
      ),
      listBody: true,
    );
    expect(hint, findsOneWidget);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(hint, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

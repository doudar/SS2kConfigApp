import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_finale.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    VoidCallback exported, {
    bool reduced = false,
  }) async {
    final session = ArcadeSession()..effectsEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await ArcadeFinale.show(context, session);
                exported();
              },
              child: const Text('FINISH'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('FINISH'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('save waits for celebration; rider can continue immediately', (
    tester,
  ) async {
    var exports = 0;
    await open(tester, () => exports++);
    expect(exports, 0);
    expect(find.text('CONTINUE TO SAVE RIDE'), findsOneWidget);
    await tester.tap(find.text('CONTINUE TO SAVE RIDE'));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'celebration pauses in background and automatically continues once',
    (tester) async {
      var exports = 0;
      await open(tester, () => exports++);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 20));
      expect(exports, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion keeps a readable ending and accessible save shortcut',
    (tester) async {
      var exports = 0;
      await open(tester, () => exports++, reduced: true);
      await tester.pump(const Duration(seconds: 2));
      expect(exports, 0);
      expect(find.text('CONTINUE TO SAVE RIDE'), findsOneWidget);
      await tester.tap(find.text('CONTINUE TO SAVE RIDE'));
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

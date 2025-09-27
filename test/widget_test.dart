// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/main.dart' as app;

void main() {
  testWidgets('App builds without crashing', (tester) async {
    // Pump the real app entrypoint
    app.main();
    await tester.pumpAndSettle();

    // Basic sanity check: at least one widget is present
    expect(find.byType(Object), findsWidgets);
  });
}

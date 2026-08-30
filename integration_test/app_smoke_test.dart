import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss2kconfigapp/main.dart' as app;
import 'package:ss2kconfigapp/main.dart' show SmartSpin2kApp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches the real application', (tester) async {
    app.main();
    await tester.pump();

    expect(find.byType(SmartSpin2kApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

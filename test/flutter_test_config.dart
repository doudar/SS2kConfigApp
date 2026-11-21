import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Host-side Flutter tests have no OS keychain plugin.
  FlutterSecureStorage.setMockInitialValues({});
  await testMain();
}

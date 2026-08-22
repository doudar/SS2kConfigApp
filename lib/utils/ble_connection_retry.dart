import 'dart:async';

class BleConnectionAttemptsExhausted implements Exception {
  const BleConnectionAttemptsExhausted({
    required this.attempts,
    required this.cause,
  });

  final int attempts;
  final Object cause;

  String get message =>
      'Unable to connect to SmartSpin2k over Bluetooth after $attempts attempts. '
      'Move closer to the device, make sure it is powered on, then try again.';

  @override
  String toString() => message;
}

/// Retries establishment of a physical BLE connection.
///
/// Returns false when the owning connection flow is cancelled. Connection
/// setup and service discovery deliberately remain outside this helper.
Future<bool> retryBleConnection({
  required Future<void> Function() connect,
  required bool Function() isConnected,
  required bool Function() isCancelled,
  int maxAttempts = 10,
  Duration retryDelay = const Duration(seconds: 1),
  void Function(int attempt, Object error)? onAttemptFailed,
}) async {
  assert(maxAttempts > 0);

  Object? lastError;
  StackTrace? lastStackTrace;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (isCancelled()) return false;

    try {
      if (!isConnected()) await connect();
      if (isConnected()) return true;
      throw StateError('BLE connect completed without an active connection.');
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      onAttemptFailed?.call(attempt, error);
    }

    if (attempt < maxAttempts && !isCancelled()) {
      await Future<void>.delayed(retryDelay);
    }
  }

  if (isCancelled()) return false;
  Error.throwWithStackTrace(
    BleConnectionAttemptsExhausted(attempts: maxAttempts, cause: lastError!),
    lastStackTrace!,
  );
}

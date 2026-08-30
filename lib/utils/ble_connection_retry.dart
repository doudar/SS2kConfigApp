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

/// A custom-characteristic write never left the app: no live DIRCON session and
/// no connected BLE characteristic to write to.
///
/// Distinct from [TransportResponseUnconfirmed] on purpose — these are
/// different facts and callers must be able to tell them apart. A settings
/// sweep aborts immediately on this one; the rest of the sweep would only
/// throw identically.
class TransportNotConnected implements Exception {
  const TransportNotConnected([this.detail]);

  final String? detail;

  @override
  String toString() => detail == null
      ? 'SmartSpin2k is not connected.'
      : 'SmartSpin2k is not connected: $detail';
}

/// A custom-characteristic write went out over a connected transport, but no
/// response bearing the matching reference arrived within the response timeout.
///
/// The write may still have landed — the device may simply be slow or its log
/// buffer full. The three-strike [DeviceData.customResponsesDegraded] breaker
/// is the arbiter of whether the link is actually dead; a single one of these
/// is within normal jitter and a sweep continues past it.
class TransportResponseUnconfirmed implements Exception {
  const TransportResponseUnconfirmed();

  @override
  String toString() =>
      'SmartSpin2k did not confirm the write within the response timeout.';
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

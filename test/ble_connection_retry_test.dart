import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_connection_retry.dart';
import 'package:ss2kconfigapp/utils/snackbar.dart';

void main() {
  test('retries transient BLE connection failures', () async {
    var attempts = 0;
    var connected = false;

    final result = await retryBleConnection(
      connect: () async {
        attempts++;
        if (attempts < 3) throw Exception('GATT 133');
        connected = true;
      },
      isConnected: () => connected,
      isCancelled: () => false,
      retryDelay: Duration.zero,
    );

    expect(result, isTrue);
    expect(attempts, 3);
  });

  test('rethrows the final error after all attempts fail', () async {
    var attempts = 0;

    await expectLater(
      retryBleConnection(
        connect: () async {
          attempts++;
          throw StateError('still unavailable');
        },
        isConnected: () => false,
        isCancelled: () => false,
        maxAttempts: 3,
        retryDelay: Duration.zero,
      ),
      throwsA(
        isA<BleConnectionAttemptsExhausted>()
            .having((error) => error.attempts, 'attempts', 3)
            .having((error) => error.cause, 'cause', isA<StateError>())
            .having(
              (error) => error.message,
              'message',
              contains('Move closer to the device'),
            ),
      ),
    );
    expect(attempts, 3);
  });

  test('stops retrying when the connection flow is cancelled', () async {
    var attempts = 0;
    var cancelled = false;

    final result = await retryBleConnection(
      connect: () async {
        attempts++;
        cancelled = true;
        throw Exception('disconnected by user');
      },
      isConnected: () => false,
      isCancelled: () => cancelled,
      retryDelay: Duration.zero,
    );

    expect(result, isFalse);
    expect(attempts, 1);
  });

  test('formats exhausted retries as actionable user feedback', () {
    final error = BleConnectionAttemptsExhausted(
      attempts: 10,
      cause: Exception('GATT 133'),
    );

    expect(
      prettyException('Connect Error:', error),
      'Connect Error: Unable to connect to SmartSpin2k over Bluetooth after '
      '10 attempts. Move closer to the device, make sure it is powered on, '
      'then try again.',
    );
  });
}

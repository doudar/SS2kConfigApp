import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/smartspin_advertisement.dart';

void main() {
  test('extracts SmartSpin IP from manufacturer payload', () {
    final ip = SmartSpinAdvertisement.ipAddress({
      0xffff: [0x53, 0x53, 1, 192, 168, 1, 149],
    });

    expect(ip, '192.168.1.149');
  });

  test('accepts payloads that still include the company identifier', () {
    final ip = SmartSpinAdvertisement.ipAddress({
      0xffff: [0xff, 0xff, 0x53, 0x53, 1, 10, 0, 0, 42],
    });

    expect(ip, '10.0.0.42');
  });

  test('rejects unrelated, unspecified, and unsupported payloads', () {
    expect(
      SmartSpinAdvertisement.ipAddress({
        1: [0x53, 0x53, 1, 1, 2, 3, 4],
      }),
      isNull,
    );
    expect(
      SmartSpinAdvertisement.ipAddress({
        0xffff: [0x53, 0x53, 1, 0, 0, 0, 0],
      }),
      isNull,
    );
    expect(
      SmartSpinAdvertisement.ipAddress({
        0xffff: [0x53, 0x53, 2, 1, 2, 3, 4],
      }),
      isNull,
    );
  });
}

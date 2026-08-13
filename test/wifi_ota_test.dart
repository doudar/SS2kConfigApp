import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/wifi_ota.dart';

void main() {
  test('multipart request reports actual streamed byte progress', () async {
    final updates = <(int, int)>[];
    final request = ProgressMultipartRequest(
      'POST',
      Uri.parse('http://smartspin2k/update'),
      onUploadProgress: (sent, total) => updates.add((sent, total)),
    );
    request.files.add(
      WifiOTA.createFirmwareMultipart(
        List<int>.filled(64 * 1024, 0x5a),
        'S3firmware.bin',
      ),
    );

    final body = await request.finalize().toBytes();

    expect(updates, isNotEmpty);
    expect(updates.length, greaterThan(4));
    expect(
      updates.map((update) => update.$1),
      orderedEquals(updates.map((update) => update.$1).toList()..sort()),
    );
    expect(updates.last.$1, body.length);
    expect(updates.last.$2, body.length);
  });

  test('returns the firmware rejection message from the HTTP response', () {
    final result = WifiOTA.resultForResponse(
      400,
      'Rejected firmware image: wrong chip.',
    );

    expect(result.outcome, WifiOtaOutcome.rejected);
    expect(result.shouldFallBackToBluetooth, isFalse);
    expect(result.message, 'Rejected firmware image: wrong chip.');
  });

  test('accepts only successful HTTP responses', () {
    final result = WifiOTA.resultForResponse(200, 'OK');

    expect(result.accepted, isTrue);
    expect(result.statusCode, 200);
  });

  test('uses the S3 firmware filename in the multipart upload', () {
    final part = WifiOTA.createFirmwareMultipart([
      0xe9,
      0x00,
    ], 'S3firmware.bin');

    expect(part.field, 'update');
    expect(part.filename, 'S3firmware.bin');
  });

  test('uses the legacy firmware filename in the multipart upload', () {
    final part = WifiOTA.createFirmwareMultipart([0xe9, 0x00], 'firmware.bin');

    expect(part.filename, 'firmware.bin');
  });

  test('DIRCON address is the first WiFi OTA candidate', () {
    expect(
      WifiOTA.candidateBaseUrls(
        deviceName: 'SmartSpin2k',
        deviceIp: '192.168.1.42',
        mdnsIp: '192.168.1.43',
      ),
      [
        'http://192.168.1.42',
        'http://192.168.1.43',
        'http://SmartSpin2k.local',
        'http://SmartSpin2k',
      ],
    );
  });

  test('duplicate discovered addresses are tried only once', () {
    expect(
      WifiOTA.candidateBaseUrls(
        deviceName: 'SmartSpin2k',
        deviceIp: '192.168.1.42',
        mdnsIp: '192.168.1.42',
      ),
      ['http://192.168.1.42', 'http://SmartSpin2k.local', 'http://SmartSpin2k'],
    );
  });
}

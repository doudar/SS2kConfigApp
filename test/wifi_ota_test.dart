import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      ),
      ['http://192.168.1.42', 'http://SmartSpin2k.local'],
    );
  });

  test('hostname is used when no advertised IP is available', () {
    expect(WifiOTA.candidateBaseUrls(deviceName: 'SmartSpin2k'), [
      'http://SmartSpin2k.local',
    ]);
  });

  test('WiFi endpoint checks share a short deadline', () {
    expect(WifiOTA.endpointStageTimeout, const Duration(seconds: 3));
  });

  test(
    'probes advertised IP and hostname in parallel before fallback',
    () async {
      final requestedHosts = <String>[];
      final client = MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == '192.0.2.1') {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        return http.Response('Not found', 404);
      });

      final result = await WifiOTA.updateFirmware(
        deviceName: 'SmartSpin2k',
        deviceIp: '192.0.2.1',
        firmwarePath: 'unused.bin',
        firmwareFilename: 'firmware.bin',
        onProgress: (_) {},
        client: client,
        endpointTimeout: const Duration(milliseconds: 10),
      );

      expect(requestedHosts, containsAll(['192.0.2.1', 'smartspin2k.local']));
      expect(result.outcome, WifiOtaOutcome.unavailable);
      expect(result.shouldFallBackToBluetooth, isTrue);
    },
  );
}

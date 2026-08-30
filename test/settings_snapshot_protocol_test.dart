import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/settings_snapshot_protocol.dart';

List<int> _chunk(int index, int count, List<int> payload) => <int>[
  0x80,
  settingsSnapshotReference,
  settingsSnapshotVersion,
  index & 0xff,
  index >> 8,
  count & 0xff,
  count >> 8,
  ...payload,
];

void main() {
  test('reassembles out-of-order UTF-8 JSON chunks', () {
    final decoder = SettingsSnapshotDecoder();
    final bytes = utf8.encode(
      jsonEncode(<String, dynamic>{
        'deviceName': 'Velo ☃',
        'shiftStep': 1250,
        'stealthChop': true,
      }),
    );
    final first = bytes.sublist(0, 11);
    final second = bytes.sublist(11, 23);
    final third = bytes.sublist(23);

    expect(decoder.add(_chunk(1, 3, second)), isNull);
    expect(decoder.add(_chunk(0, 3, first)), isNull);
    final snapshot = decoder.add(_chunk(2, 3, third));

    expect(snapshot, <String, dynamic>{
      'deviceName': 'Velo ☃',
      'shiftStep': 1250,
      'stealthChop': true,
    });
    expect(decoder.receivedChunkCount, 0);
    expect(decoder.expectedChunkCount, isNull);
  });

  test('accepts identical duplicate chunks but rejects changed duplicates', () {
    final decoder = SettingsSnapshotDecoder();
    final first = _chunk(0, 2, utf8.encode('{"deviceName":'));

    expect(decoder.add(first), isNull);
    expect(decoder.add(first), isNull);
    expect(
      () => decoder.add(_chunk(0, 2, utf8.encode('{"shiftStep":'))),
      throwsFormatException,
    );
  });

  test('rejects unsupported snapshot framing versions', () {
    final packet = _chunk(0, 1, utf8.encode('{}'));
    packet[2] = settingsSnapshotVersion + 1;

    expect(() => SettingsSnapshotDecoder().add(packet), throwsFormatException);
  });

  test('recognizes only an explicit 0x31 error as unsupported', () {
    expect(
      isUnsupportedSettingsSnapshotPacket(<int>[
        0xff,
        settingsSnapshotReference,
      ]),
      isTrue,
    );
    expect(
      isUnsupportedSettingsSnapshotPacket(<int>[
        0x80,
        settingsSnapshotReference,
      ]),
      isFalse,
    );
    expect(isUnsupportedSettingsSnapshotPacket(<int>[0xff, 0x30]), isFalse);
    expect(isUnsupportedSettingsSnapshotPacket(<int>[]), isFalse);
  });

  test('falls back only for an explicit unsupported result', () async {
    var individualRequests = 0;

    final supported = await requestSettingsWithSnapshotFallback(
      requestSnapshot: () async => SettingsSnapshotRequestResult.supported,
      requestIndividually: () async => individualRequests++,
    );
    expect(supported, SettingsSnapshotRequestResult.supported);
    expect(individualRequests, 0);

    final unsupported = await requestSettingsWithSnapshotFallback(
      requestSnapshot: () async => SettingsSnapshotRequestResult.unsupported,
      requestIndividually: () async => individualRequests++,
    );
    expect(unsupported, SettingsSnapshotRequestResult.unsupported);
    expect(individualRequests, 1);

    await expectLater(
      requestSettingsWithSnapshotFallback(
        requestSnapshot: () async => throw TimeoutException('missing chunk'),
        requestIndividually: () async => individualRequests++,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(individualRequests, 1);
  });

  test('maps known JSON keys and ignores future firmware properties', () {
    final values = settingsSnapshotValuesByReference(<String, dynamic>{
      'firmwareVersion': '26.8.30',
      'deviceName': 'SmartBench',
      'minWatts': 45,
      'maxWatts': 1200,
      'pTab4Pwr': true,
      'futureSetting': 123,
    }, createCustomCharacteristicFramework());

    expect(values, <int, dynamic>{
      0x25: '26.8.30',
      0x07: 'SmartBench',
      0x21: 45,
      0x22: 1200,
      0x2d: true,
    });
  });

  test(
    'new conventionally named characteristics need no snapshot registry',
    () {
      final values = settingsSnapshotValuesByReference(
        <String, dynamic>{'futureSetting': 123},
        <Map<String, dynamic>>[
          <String, dynamic>{'vName': 'BLE_futureSetting', 'reference': '0x33'},
        ],
      );

      expect(values, <int, dynamic>{0x33: 123});
    },
  );
}

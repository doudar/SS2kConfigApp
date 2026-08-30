import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_scan_results_protocol.dart';

List<int> packet({
  required BleScanResultEvent event,
  required int scanId,
  required int sequence,
  int fragment = 0,
  int fragmentCount = 1,
  List<int> payload = const [],
}) => [
  0x80,
  bleScanResultsReference,
  bleScanResultsVersion,
  event.index,
  scanId & 0xff,
  scanId >> 8,
  sequence & 0xff,
  sequence >> 8,
  fragment,
  fragmentCount,
  ...payload,
];

List<int> deviceBody(String uuid, String name) {
  final uuidBytes = utf8.encode(uuid);
  return [uuidBytes.length, ...uuidBytes, ...utf8.encode(name)];
}

void main() {
  test(
    'reassembles more devices than the legacy JSON characteristic can hold',
    () {
      final decoder = BleScanResultStreamDecoder();
      decoder.add(
        packet(event: BleScanResultEvent.begin, scanId: 7, sequence: 0),
      );

      for (var i = 0; i < 40; i++) {
        decoder.add(
          packet(
            event: BleScanResultEvent.device,
            scanId: 7,
            sequence: i,
            payload: deviceBody('0x1818', 'Power Meter $i'),
          ),
        );
      }
      final end = decoder.add(
        packet(event: BleScanResultEvent.end, scanId: 7, sequence: 40),
      );

      expect(end?.isComplete, isTrue);
      expect(end?.devices, hasLength(40));
      expect(end?.devices.last.name, 'Power Meter 39');
    },
  );

  test('reassembles a record fragmented for the minimum ATT MTU', () {
    final decoder = BleScanResultStreamDecoder();
    final body = deviceBody(
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
      'A long sensor name',
    );
    final fragments = <List<int>>[];
    for (var offset = 0; offset < body.length; offset += 10) {
      fragments.add(body.sublist(offset, (offset + 10).clamp(0, body.length)));
    }

    decoder.add(
      packet(event: BleScanResultEvent.begin, scanId: 9, sequence: 0),
    );
    for (var i = 0; i < fragments.length; i++) {
      decoder.add(
        packet(
          event: BleScanResultEvent.device,
          scanId: 9,
          sequence: 0,
          fragment: i,
          fragmentCount: fragments.length,
          payload: fragments[i],
        ),
      );
    }
    final end = decoder.add(
      packet(event: BleScanResultEvent.end, scanId: 9, sequence: 1),
    );

    expect(end?.isComplete, isTrue);
    expect(end?.devices.single.name, 'A long sensor name');
    expect(end?.devices.single.uuid, '6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  });

  test('reports an incomplete stream when a notification is missing', () {
    final decoder = BleScanResultStreamDecoder();
    decoder.add(
      packet(event: BleScanResultEvent.begin, scanId: 11, sequence: 0),
    );
    final body = deviceBody('0x180d', 'Heart Rate');
    decoder.add(
      packet(
        event: BleScanResultEvent.device,
        scanId: 11,
        sequence: 0,
        fragmentCount: 2,
        payload: body.sublist(0, 5),
      ),
    );
    final end = decoder.add(
      packet(event: BleScanResultEvent.end, scanId: 11, sequence: 1),
    );

    expect(end?.isComplete, isFalse);
    expect(end?.devices, isEmpty);
  });
}

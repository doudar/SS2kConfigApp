import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_log_buffer.dart';

void main() {
  test(
    'counts UTF-8 bytes and export separators, evicting complete messages',
    () {
      final buffer = DeviceLogBuffer(maxBytes: 12);
      buffer.add('abc');
      buffer.add('é🚲');
      expect(buffer.byteLength, 10);
      buffer.add('x');
      expect(buffer.byteLength, 12);
      expect(buffer.messages, ['abc', 'é🚲', 'x']);
      buffer.add('last');
      expect(buffer.messages, ['x', 'last']);
      expect(buffer.byteLength, utf8.encode(buffer.messages.join('\n')).length);
    },
  );

  test('sustained logging retains the most recent messages within 200 KB', () {
    final buffer = DeviceLogBuffer();
    for (var i = 0; i < 20000; i++) {
      buffer.add('[$i] SmartSpin2k calibration progress 🚲');
      expect(buffer.byteLength, lessThanOrEqualTo(200 * 1024));
    }
    expect(buffer.messages.last, '[19999] SmartSpin2k calibration progress 🚲');
    expect(buffer.messages.first, isNot(startsWith('[0]')));
    expect(buffer.byteLength, utf8.encode(buffer.messages.join('\n')).length);
  });

  test(
    'clear resets accounting; empty and oversized messages preserve history',
    () {
      final buffer = DeviceLogBuffer(maxBytes: 4)..add('abcd');
      buffer.add('');
      buffer.add('oversized');
      expect(buffer.messages, ['abcd']);
      expect(buffer.byteLength, 4);
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.byteLength, 0);
      buffer.add('éé');
      expect(buffer.messages, ['éé']);
      expect(buffer.byteLength, 4);
    },
  );
}

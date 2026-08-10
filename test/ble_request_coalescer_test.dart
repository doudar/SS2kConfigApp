import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_request_coalescer.dart';

void main() {
  test('coalesces identical custom read packets until completion', () async {
    final coalescer = CustomReadRequestCoalescer();
    final completion = Completer<void>();
    var operationCount = 0;

    Future<void> operation(List<int> packet) {
      operationCount++;
      return completion.future;
    }

    final first = coalescer.schedule(<int>[0x01, 0x17], operation);
    final duplicate = coalescer.schedule(<int>[0x01, 0x17], operation);

    expect(identical(first, duplicate), isTrue);
    expect(operationCount, 1);

    completion.complete();
    await first;
    await Future<void>.delayed(Duration.zero);

    await coalescer.schedule(
      <int>[0x01, 0x17],
      (packet) async => operationCount++,
    );
    expect(operationCount, 2);
  });

  test('does not coalesce different indexed read packets', () async {
    final coalescer = CustomReadRequestCoalescer();
    final completions = <Completer<void>>[
      Completer<void>(),
      Completer<void>(),
    ];
    var operationCount = 0;

    Future<void> operation(List<int> packet) {
      return completions[operationCount++].future;
    }

    final firstRow = coalescer.schedule(<int>[0x01, 0x27, 0x00], operation);
    final secondRow = coalescer.schedule(<int>[0x01, 0x27, 0x01], operation);

    expect(identical(firstRow, secondRow), isFalse);
    expect(operationCount, 2);

    for (final completion in completions) {
      completion.complete();
    }
    await Future.wait(<Future<void>>[firstRow, secondRow]);
  });

  test('never coalesces custom write packets', () async {
    final coalescer = CustomReadRequestCoalescer();
    var operationCount = 0;

    Future<void> operation(List<int> packet) async {
      operationCount++;
    }

    await Future.wait(<Future<void>>[
      coalescer.schedule(<int>[0x02, 0x17, 0x01], operation),
      coalescer.schedule(<int>[0x02, 0x17, 0x01], operation),
    ]);

    expect(operationCount, 2);
  });
}

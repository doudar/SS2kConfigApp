import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';
import 'package:ss2kconfigapp/utils/dircon_client.dart';

void main() {
  test('parses fragmented and coalesced DIRCON frames', () {
    final parser = DirConFrameParser();

    expect(parser.add([1, 1, 7]), isEmpty);
    final frames = parser.add([0, 0, 2, 0xaa, 0xbb, 1, 6, 0, 0, 0, 1, 0xcc]);

    expect(frames, hasLength(2));
    expect(frames[0].identifier, 1);
    expect(frames[0].sequence, 7);
    expect(frames[0].body, [0xaa, 0xbb]);
    expect(frames[1].identifier, 6);
    expect(frames[1].sequence, 0);
    expect(frames[1].body, [0xcc]);
  });

  test('encodes the FTMS spin-down command sent over DIRCON', () {
    expect(FTMSControlPoint.spinDownCommand(true), [0x13, 0x01]);
    expect(FTMSControlPoint.spinDownCommand(false), [0x13, 0x02]);
  });

  group('DIRCON response timeout', () {
    test(
      'invalidates a silent connection once and fails pending requests',
      () async {
        final server = await _serve((_) {});
        final client = await DirConClient.connect(
          InternetAddress.loopbackIPv4.address,
          responseTimeout: const Duration(milliseconds: 20),
          connectionPort: server.port,
        );
        var disconnects = 0;
        final subscription = client.disconnected.listen((_) => disconnects++);

        final first = client.setNotifications(_uuid, true);
        final second = client.setNotifications(_uuid, false);
        final firstResult = expectLater(
          first,
          throwsA(isA<TimeoutException>()),
        );
        final secondResult = expectLater(second, throwsA(anything));
        await Future.wait([firstResult, secondResult]);
        await Future<void>.delayed(Duration.zero);

        expect(client.isConnected, isFalse);
        expect(disconnects, 1);
        await expectLater(
          client.setNotifications(_uuid, true),
          throwsA(isA<SocketException>()),
        );
        await client.close();
        await subscription.cancel();
        await server.close();
      },
    );

    test('accepts a response that arrives before the deadline', () async {
      final server = await _serve((socket) async {
        final request = await socket.first;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        socket.add([1, request[1], request[2], 0, 0, 0]);
      });
      final client = await DirConClient.connect(
        InternetAddress.loopbackIPv4.address,
        responseTimeout: const Duration(milliseconds: 40),
        connectionPort: server.port,
      );

      await client.setNotifications(_uuid, true);
      expect(client.isConnected, isTrue);
      await client.close();
      await server.close();
    });

    test('keeps a protocol error distinct from transport failure', () async {
      final server = await _serve((socket) async {
        final request = await socket.first;
        socket.add([1, request[1], request[2], 7, 0, 0]);
      });
      final client = await DirConClient.connect(
        InternetAddress.loopbackIPv4.address,
        responseTimeout: const Duration(milliseconds: 40),
        connectionPort: server.port,
      );

      await expectLater(
        client.setNotifications(_uuid, true),
        throwsA(isA<StateError>()),
      );
      expect(client.isConnected, isTrue);
      await client.close();
      await server.close();
    });

    test('late socket activity cannot emit a second disconnect', () async {
      final server = await _serve((socket) async {
        final request = await socket.first;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        socket.add([1, request[1], request[2], 0, 0, 0]);
        await socket.close();
      });
      final client = await DirConClient.connect(
        InternetAddress.loopbackIPv4.address,
        responseTimeout: const Duration(milliseconds: 10),
        connectionPort: server.port,
      );
      var disconnects = 0;
      final subscription = client.disconnected.listen((_) => disconnects++);

      await expectLater(
        client.setNotifications(_uuid, true),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(disconnects, 1);
      await client.close();
      await subscription.cancel();
      await server.close();
    });

    test('explicit close racing a timeout is safe', () async {
      final server = await _serve((_) {});
      final client = await DirConClient.connect(
        InternetAddress.loopbackIPv4.address,
        responseTimeout: const Duration(milliseconds: 20),
        connectionPort: server.port,
      );
      final request = client.setNotifications(_uuid, true);
      final requestResult = expectLater(
        request,
        throwsA(isA<SocketException>()),
      );
      await client.close();
      await requestResult;
      expect(client.isConnected, isFalse);
      await server.close();
    });
  });
}

const _uuid = '00000000-0000-0000-0000-000000000001';

Future<ServerSocket> _serve(
  FutureOr<void> Function(Socket socket) handler,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    unawaited(Future<void>.sync(() => handler(socket)));
  });
  return server;
}

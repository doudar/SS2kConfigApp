import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class DirConFrame {
  const DirConFrame({
    required this.identifier,
    required this.sequence,
    required this.responseCode,
    required this.body,
  });

  final int identifier;
  final int sequence;
  final int responseCode;
  final Uint8List body;
}

class DirConFrameParser {
  final List<int> _buffer = [];

  List<DirConFrame> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final frames = <DirConFrame>[];
    while (_buffer.length >= 6) {
      final bodyLength = (_buffer[4] << 8) | _buffer[5];
      final frameLength = 6 + bodyLength;
      if (_buffer.length < frameLength) break;

      frames.add(
        DirConFrame(
          identifier: _buffer[1],
          sequence: _buffer[2],
          responseCode: _buffer[3],
          body: Uint8List.fromList(_buffer.sublist(6, frameLength)),
        ),
      );
      _buffer.removeRange(0, frameLength);
    }
    return frames;
  }
}

class DirConClient {
  DirConClient._(this.host, this._socket, {required this.responseTimeout});

  static const int port = 8081;
  static const int success = 0;
  static const int discoverServicesMessage = 0x01;
  static const int discoverCharacteristicsMessage = 0x02;
  static const int readCharacteristicMessage = 0x03;
  static const int writeCharacteristicMessage = 0x04;
  static const int enableNotificationsMessage = 0x05;
  static const int notificationMessage = 0x06;
  static const bool diagnosticsEnabled = !bool.fromEnvironment(
    'dart.vm.product',
  );
  static const int _wifiPasswordReference = 0x13;

  final String host;
  final Socket _socket;
  final Duration responseTimeout;
  final DirConFrameParser _parser = DirConFrameParser();
  final Map<int, Completer<DirConFrame>> _pending = {};
  final StreamController<DirConFrame> _notifications =
      StreamController<DirConFrame>.broadcast();
  final StreamController<void> _disconnected =
      StreamController<void>.broadcast();
  StreamSubscription<List<int>>? _subscription;
  int _nextSequence = 1;
  bool _isClosed = false;
  bool _isDisposed = false;
  bool _disconnectEmitted = false;
  Future<void>? _resourceClose;

  bool get isConnected => !_isClosed;
  Stream<DirConFrame> get notifications => _notifications.stream;
  Stream<void> get disconnected => _disconnected.stream;

  static Future<DirConClient> connect(
    String host, {
    Duration timeout = const Duration(milliseconds: 1200),
    Duration responseTimeout = const Duration(seconds: 5),
    int connectionPort = port,
  }) async {
    _log('CONNECT', '$host:$connectionPort');
    final socket = await Socket.connect(host, connectionPort, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = DirConClient._(
      host,
      socket,
      responseTimeout: responseTimeout,
    );
    client._listen();
    _log('CONNECTED', '${socket.address.address}:${socket.remotePort}');
    return client;
  }

  void _listen() {
    _subscription = _socket.listen(
      (bytes) {
        _log('RX-SOCKET', '${bytes.length} bytes');
        for (final frame in _parser.add(bytes)) {
          _logFrame(
            'RX',
            frame.identifier,
            frame.sequence,
            frame.responseCode,
            frame.body,
          );
          if (frame.identifier == notificationMessage) {
            _notifications.add(frame);
          } else {
            _pending.remove(frame.sequence)?.complete(frame);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _closeWithError(error, stackTrace);
      },
      onDone: () => _closeWithError(
        const SocketException('DIRCON connection closed'),
        StackTrace.current,
      ),
      cancelOnError: true,
    );
    // Write failures land on the sink's done future rather than on the read
    // subscription. Observe it so a failed write tears the client down instead
    // of surfacing as an unhandled asynchronous error.
    unawaited(
      _socket.done.then(
        (_) {},
        onError: (Object error, StackTrace stackTrace) =>
            _closeWithError(error, stackTrace),
      ),
    );
  }

  Future<void> initialize({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await ensureCharacteristic(
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      enableNotifications: true,
    );
  }

  Future<void> ensureCharacteristic({
    required String serviceUuid,
    required String characteristicUuid,
    bool enableNotifications = false,
  }) async {
    final services = await discoverServices();
    final normalizedService = _normalizeUuid(serviceUuid);
    if (!services.contains(normalizedService)) {
      throw StateError('SmartSpin2k DIRCON service not found');
    }

    final characteristics = await discoverCharacteristics(serviceUuid);
    final normalizedCharacteristic = _normalizeUuid(characteristicUuid);
    if (!characteristics.contains(normalizedCharacteristic)) {
      throw StateError('SmartSpin2k DIRCON characteristic not found');
    }
    if (enableNotifications) {
      await setNotifications(characteristicUuid, true);
    }
  }

  Future<List<String>> discoverServices() async {
    final response = await _request(discoverServicesMessage, const []);
    if (response.body.length % 16 != 0) {
      throw const FormatException('Invalid DIRCON service response');
    }
    return [
      for (var offset = 0; offset < response.body.length; offset += 16)
        _uuidFromBytes(response.body.sublist(offset, offset + 16)),
    ];
  }

  Future<List<String>> discoverCharacteristics(String serviceUuid) async {
    final response = await _request(
      discoverCharacteristicsMessage,
      _uuidBytes(serviceUuid),
    );
    if (response.body.length < 16 || (response.body.length - 16) % 17 != 0) {
      throw const FormatException('Invalid DIRCON characteristic response');
    }
    return [
      for (var offset = 16; offset < response.body.length; offset += 17)
        _uuidFromBytes(response.body.sublist(offset, offset + 16)),
    ];
  }

  Future<void> setNotifications(String characteristicUuid, bool enabled) async {
    await _request(enableNotificationsMessage, [
      ..._uuidBytes(characteristicUuid),
      if (enabled) 1 else 0,
    ]);
  }

  Future<List<int>> writeCharacteristic(
    String characteristicUuid,
    List<int> value,
  ) async {
    final response = await _request(writeCharacteristicMessage, [
      ..._uuidBytes(characteristicUuid),
      ...value,
    ]);
    if (response.body.length < 16) {
      throw const FormatException('Invalid DIRCON write response');
    }
    return response.body.sublist(16);
  }

  Stream<List<int>> characteristicNotifications(String characteristicUuid) {
    final expected = _normalizeUuid(characteristicUuid);
    return notifications
        .where((frame) {
          return frame.body.length >= 16 &&
              _uuidFromBytes(frame.body.sublist(0, 16)) == expected;
        })
        .map((frame) => frame.body.sublist(16));
  }

  Future<DirConFrame> _request(int identifier, List<int> body) async {
    if (_isClosed) throw const SocketException('DIRCON client is closed');

    final sequence = _nextSequence;
    _nextSequence = _nextSequence == 255 ? 1 : _nextSequence + 1;
    final completer = Completer<DirConFrame>();
    _pending[sequence] = completer;
    final length = body.length;
    _logFrame('TX', identifier, sequence, 0, body);
    try {
      _socket.add([
        1,
        identifier,
        sequence,
        0,
        length >> 8,
        length & 0xff,
        ...body,
      ]);
      // Deliberately no `flush()`. It binds the socket sink until it resolves,
      // so a concurrent request's `add()` throws "StreamSink is bound to a
      // stream", and awaiting it opens a gap in which a close or another
      // request's timeout can fail this request before anything listens for
      // the result. Writes are queued in order; failures arrive via
      // `_socket.done`. Creating and awaiting the timeout in one step keeps
      // the response error observed from the moment it can be raised.
      final response = await completer.future.timeout(responseTimeout);
      if (response.identifier != identifier) {
        throw StateError('Unexpected DIRCON response type');
      }
      if (response.responseCode != success) {
        throw StateError(
          'DIRCON request failed with code ${response.responseCode}',
        );
      }
      return response;
    } on TimeoutException catch (error, stackTrace) {
      // Teardown clears `_pending`, so a still-registered completer means this
      // request is the one that actually went silent rather than one failed by
      // another request's timeout. A response timeout is transport liveness
      // failure, not a protocol response: invalidate synchronously so callers
      // cannot schedule another workout write against this half-open session.
      if (_pending.remove(sequence) != null) {
        _log('TIMEOUT', '$host request type=0x${identifier.toRadixString(16)}');
        _closeWithError(error, stackTrace);
      }
      rethrow;
    } on SocketException catch (error, stackTrace) {
      _closeWithError(error, stackTrace);
      rethrow;
    } finally {
      _pending.remove(sequence);
    }
  }

  Future<void> close() async {
    if (_isDisposed) {
      await _resourceClose;
      return;
    }
    _isDisposed = true;
    _isClosed = true;
    _log('CLOSE', host);
    final error = const SocketException('DIRCON client closed');
    _failPending(error, StackTrace.current);
    await _releaseResources();
  }

  void _closeWithError(Object error, StackTrace stackTrace) {
    if (_isClosed) return;
    _isClosed = true;
    _log('DISCONNECTED', '$host: $error');
    _failPending(error, stackTrace);
    if (!_disconnectEmitted && !_disconnected.isClosed) {
      _disconnectEmitted = true;
      _disconnected.add(null);
    }
    unawaited(_releaseResources());
  }

  void _failPending(Object error, StackTrace stackTrace) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    _pending.clear();
  }

  Future<void> _releaseResources() {
    return _resourceClose ??= _releaseResourcesInner();
  }

  Future<void> _releaseResourcesInner() async {
    await _subscription?.cancel();
    // The read subscription can be in its terminal callback while an explicit
    // close or timeout starts teardown. `Socket.close()` rejects that race with
    // "StreamSink is bound to a stream"; destroy is the idempotent terminal
    // operation for this unusable transport.
    _socket.destroy();
    if (!_notifications.isClosed) await _notifications.close();
    if (!_disconnected.isClosed) await _disconnected.close();
  }

  static List<int> _uuidBytes(String uuid) {
    final hex = _normalizeUuid(uuid).replaceAll('-', '');
    if (hex.length != 32) throw const FormatException('Invalid UUID');
    return [
      for (var offset = 0; offset < hex.length; offset += 2)
        int.parse(hex.substring(offset, offset + 2), radix: 16),
    ];
  }

  static String _uuidFromBytes(List<int> bytes) {
    if (bytes.length != 16) throw const FormatException('Invalid UUID bytes');
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String _normalizeUuid(String uuid) => uuid.toLowerCase();

  static void _logFrame(
    String direction,
    int identifier,
    int sequence,
    int responseCode,
    List<int> body,
  ) {
    if (!diagnosticsEnabled) return;
    _log(
      direction,
      'type=${_messageName(identifier)} '
      '(0x${identifier.toRadixString(16).padLeft(2, '0')}) '
      'seq=$sequence status=$responseCode body=${body.length}B '
      '${_safeBodyHex(identifier, body)}',
    );
  }

  static String _safeBodyHex(int identifier, List<int> body) {
    var visible = body;
    var suffix = '';

    // Characteristic write requests, responses, and notifications start with
    // a 16-byte UUID. The following custom-characteristic packet contains its
    // operation and reference. Never print Wi-Fi password bytes.
    if ((identifier == writeCharacteristicMessage ||
            identifier == notificationMessage) &&
        body.length >= 18 &&
        body[17] == _wifiPasswordReference) {
      visible = body.sublist(0, 18);
      suffix = ' <password payload redacted>';
    } else if (body.length > 96) {
      visible = body.sublist(0, 96);
      suffix = ' ...(+${body.length - visible.length}B)';
    }

    return '[${visible.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ')}]$suffix';
  }

  static String _messageName(int identifier) {
    switch (identifier) {
      case discoverServicesMessage:
        return 'discover-services';
      case discoverCharacteristicsMessage:
        return 'discover-characteristics';
      case readCharacteristicMessage:
        return 'read-characteristic';
      case writeCharacteristicMessage:
        return 'write-characteristic';
      case enableNotificationsMessage:
        return 'notifications';
      case notificationMessage:
        return 'notification';
      default:
        return 'unknown';
    }
  }

  static void _log(String event, String message) {
    if (diagnosticsEnabled) print('[DIRCON][$event] $message');
  }
}

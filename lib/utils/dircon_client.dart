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
  DirConClient._(this.host, this._socket);

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

  bool get isConnected => !_isClosed;
  Stream<DirConFrame> get notifications => _notifications.stream;
  Stream<void> get disconnected => _disconnected.stream;

  static Future<DirConClient> connect(
    String host, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    _log('CONNECT', '$host:$port');
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = DirConClient._(host, socket);
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
    _socket.add([
      1,
      identifier,
      sequence,
      0,
      length >> 8,
      length & 0xff,
      ...body,
    ]);
    await _socket.flush();

    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 5),
      );
      if (response.identifier != identifier) {
        throw StateError('Unexpected DIRCON response type');
      }
      if (response.responseCode != success) {
        throw StateError(
          'DIRCON request failed with code ${response.responseCode}',
        );
      }
      return response;
    } finally {
      _pending.remove(sequence);
    }
  }

  Future<void> close() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isClosed = true;
    _log('CLOSE', host);
    await _subscription?.cancel();
    await _socket.close();
    final error = const SocketException('DIRCON client closed');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    await _notifications.close();
    await _disconnected.close();
  }

  void _closeWithError(Object error, StackTrace stackTrace) {
    if (_isClosed) return;
    _isClosed = true;
    _log('DISCONNECTED', '$host: $error');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    _pending.clear();
    if (!_disconnected.isClosed) _disconnected.add(null);
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

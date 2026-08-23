import 'dart:async';
import 'dart:collection';

import 'package:ss2kconfigapp/utils/dircon_client.dart';

/// A [DirConSession] that behaves like the real client's protocol surface
/// without a socket.
///
/// UUIDs are normalized exactly as `DirConClient` normalizes them, so a test
/// may use either the lowercase spelling from `constants.dart` or the uppercase
/// spelling from `bleConstants.dart` and still match what `DeviceData` sent.
class FakeDirConSession implements DirConSession {
  FakeDirConSession({this.host = '192.168.1.50'});

  @override
  final String host;

  bool _isConnected = true;
  bool isClosed = false;

  /// Every `initialize` argument pair, in call order.
  String? initializedServiceUuid;
  String? initializedCharacteristicUuid;
  Object? initializeFailure;

  final List<({String uuid, bool enableNotifications})> ensureCalls = [];
  final List<({String uuid, List<int> value})> writes = [];

  final Map<String, Object> _characteristicFailures = {};
  final Map<String, Object> _writeFailures = {};
  final Map<String, List<int>> _writeResponses = {};
  final Map<String, List<List<int>>> _framesDuringEnable = {};
  final Map<String, StreamController<List<int>>> _notifications = {};
  final Map<String, int> _listeners = {};
  final Map<String, int> _cancellations = {};

  final StreamController<void> _disconnected =
      StreamController<void>.broadcast();

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  // ---------------------------------------------------------------- controls

  /// Makes discovery/enablement fail for [uuid], as firmware without the
  /// characteristic does.
  void failCharacteristic(String uuid, [Object? error]) {
    _characteristicFailures[_key(uuid)] =
        error ?? StateError('characteristic $uuid not found');
  }

  /// Makes writes to [uuid] fail. Per-characteristic so a bootstrap failure on
  /// the custom characteristic does not also break FTMS control.
  void failWritesFor(String uuid, [Object? error]) {
    _writeFailures[_key(uuid)] = error ?? StateError('write to $uuid failed');
  }

  void respondToWrites(String uuid, List<int> response) {
    _writeResponses[_key(uuid)] = response;
  }

  /// Queues frames the device "emits" from inside `ensureCharacteristic`, i.e.
  /// while notification enablement is still in flight. Only a subscriber that
  /// listened *before* enabling can observe them.
  void emitDuringEnable(String uuid, List<int> frame) {
    _framesDuringEnable.putIfAbsent(_key(uuid), () => []).add(frame);
  }

  void emitNotification(String uuid, List<int> frame) {
    final controller = _notifications[_key(uuid)];
    if (controller == null || controller.isClosed) return;
    controller.add(frame);
  }

  /// Simulates an unexpected transport loss.
  void dropConnection() {
    _isConnected = false;
    if (!_disconnected.isClosed) _disconnected.add(null);
  }

  // -------------------------------------------------------------- assertions

  List<List<int>> writesFor(String uuid) {
    final key = _key(uuid);
    return [
      for (final write in writes)
        if (_key(write.uuid) == key) write.value,
    ];
  }

  bool enabledNotificationsFor(String uuid) {
    final key = _key(uuid);
    return ensureCalls.any(
      (call) => _key(call.uuid) == key && call.enableNotifications,
    );
  }

  /// True once the characteristic has been looked up at all, whether or not
  /// notifications were enabled for it.
  bool discovered(String uuid) {
    final key = _key(uuid);
    return ensureCalls.any((call) => _key(call.uuid) == key);
  }

  /// True while something still holds a notification subscription for [uuid].
  /// Asserting this directly matters: a consumer-side "is the controller
  /// closed?" guard can make a leaked subscription look like a cancelled one.
  bool isListening(String uuid) => (_listeners[_key(uuid)] ?? 0) > 0;

  int cancellationsFor(String uuid) => _cancellations[_key(uuid)] ?? 0;

  // ------------------------------------------------------------ DirConSession

  @override
  Future<void> initialize({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    initializedServiceUuid = serviceUuid;
    initializedCharacteristicUuid = characteristicUuid;
    final failure = initializeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> ensureCharacteristic({
    required String serviceUuid,
    required String characteristicUuid,
    bool enableNotifications = false,
  }) async {
    ensureCalls.add((
      uuid: characteristicUuid,
      enableNotifications: enableNotifications,
    ));
    final key = _key(characteristicUuid);
    final failure = _characteristicFailures[key];
    if (failure != null) throw failure;

    // Deliberately synchronous with respect to the caller's await: these frames
    // are delivered while enablement is still in flight.
    for (final frame in _framesDuringEnable[key] ?? const <List<int>>[]) {
      final controller = _notifications[key];
      if (controller != null && !controller.isClosed) controller.add(frame);
    }
  }

  @override
  Future<List<int>> writeCharacteristic(
    String characteristicUuid,
    List<int> value,
  ) async {
    if (!_isConnected) throw StateError('DIRCON session is closed');
    writes.add((uuid: characteristicUuid, value: List<int>.from(value)));
    final key = _key(characteristicUuid);
    final failure = _writeFailures[key];
    if (failure != null) throw failure;
    return _writeResponses[key] ?? const <int>[];
  }

  @override
  Stream<List<int>> characteristicNotifications(String characteristicUuid) {
    final key = _key(characteristicUuid);
    final controller = _notifications.putIfAbsent(
      key,
      () => StreamController<List<int>>.broadcast(
        onListen: () => _listeners[key] = (_listeners[key] ?? 0) + 1,
        onCancel: () {
          _listeners[key] = (_listeners[key] ?? 1) - 1;
          _cancellations[key] = (_cancellations[key] ?? 0) + 1;
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<void> close() async {
    _isConnected = false;
    isClosed = true;
    if (!_disconnected.isClosed) await _disconnected.close();
  }

  static String _key(String uuid) => uuid.toLowerCase();
}

/// Hands out prepared [FakeDirConSession]s in order, so a reconnect test can
/// prove the first session was torn down and the second is live.
class FakeDirConConnector {
  FakeDirConConnector([List<FakeDirConSession>? sessions])
    : _queued = Queue<FakeDirConSession>.of(
        sessions ?? [FakeDirConSession()],
      );

  final Queue<FakeDirConSession> _queued;

  /// Every host `DeviceData` tried, in order.
  final List<String> hosts = [];

  /// Every session actually handed out, in order.
  final List<FakeDirConSession> issued = [];

  /// When set, the next connect attempt throws this instead of returning a
  /// session — the "DIRCON endpoint unreachable" path.
  Object? connectFailure;

  FakeDirConSession get first => issued.first;
  FakeDirConSession get last => issued.last;

  Future<DirConSession> call(String host) async {
    hosts.add(host);
    final failure = connectFailure;
    if (failure != null) throw failure;
    if (_queued.isEmpty) {
      throw StateError('FakeDirConConnector ran out of prepared sessions');
    }
    final session = _queued.removeFirst();
    issued.add(session);
    return session;
  }
}

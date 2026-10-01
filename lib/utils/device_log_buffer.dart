import 'dart:collection';
import 'dart:convert';

/// Recent complete device messages, bounded by their UTF-8 export size.
class DeviceLogBuffer {
  DeviceLogBuffer({this.maxBytes = 200 * 1024}) : assert(maxBytes > 0);

  final int maxBytes;
  final _entries = ListQueue<({String message, int bytes})>();
  int _messageBytes = 0;

  bool get isEmpty => _entries.isEmpty;
  Iterable<String> get messages => _entries.map((entry) => entry.message);
  int get byteLength =>
      _messageBytes + (_entries.isEmpty ? 0 : _entries.length - 1);

  void add(String message) {
    if (message.isEmpty) return;
    final bytes = utf8.encode(message).length;
    // Device packets are small, but a single oversized message must never
    // defeat the cap or evict the entire useful history.
    if (bytes > maxBytes) return;
    _entries.addLast((message: message, bytes: bytes));
    _messageBytes += bytes;
    while (byteLength > maxBytes) {
      _messageBytes -= _entries.removeFirst().bytes;
    }
  }

  void clear() {
    _entries.clear();
    _messageBytes = 0;
  }
}

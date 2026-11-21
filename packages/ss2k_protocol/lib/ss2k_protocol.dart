library ss2k_protocol;

import 'dart:convert';
import 'dart:typed_data';

part 'src/generated.dart';

enum ReplyKind { read, write, notification }

class CommandDescriptor {
  const CommandDescriptor(
    this.id,
    this.name,
    this.readRequest,
    this.readResponse,
    this.writeRequest,
    this.writeResponse,
    this.notification,
    this.scale,
    this.snapshotKey,
    this.completionNotification,
    this.sensitive,
  );
  final int id;
  final String name;
  final WireFormat readRequest,
      readResponse,
      writeRequest,
      writeResponse,
      notification;

  /// Raw wire integer = engineering value * scale.
  final int scale;
  final String? snapshotKey;
  final bool completionNotification, sensitive;
}

CommandDescriptor command(int id) =>
    commands[id] ??
    (throw ArgumentError.value(id, 'id', 'Unknown or reserved command'));

/// Fresh mutable app state. settingType remains a string; map it to your UI enum.
/// Defaults are presentation placeholders, not firmware factory settings.
List<Map<String, Object?>> createAppDescriptors() => [
  for (final descriptor in appDescriptors)
    Map<String, Object?>.from(descriptor),
];

Map<int, Object?> snapshotValues(Map<String, Object?> snapshot) => {
  for (final c in commands.values)
    if (c.snapshotKey != null && snapshot.containsKey(c.snapshotKey))
      c.id: snapshot[c.snapshotKey],
};

void _bytes(List<int> data) {
  if (data.any((v) => v < 0 || v > 255))
    throw const FormatException('Packet contains a non-byte value');
}

int _u16(List<int> p, int at) => p[at] | (p[at + 1] << 8);
int _signed(int value, int bits) => value.toSigned(bits);
bool _pair(int pair) {
  final front = pair ~/ gear_pair_multiplier,
      rear = pair % gear_pair_multiplier;
  if (front < 1 || front > gear_max_tooth || rear < 1 || rear > gear_max_tooth)
    return false;
  final ratio = (front * gear_ratio_scale + rear ~/ 2) ~/ rear;
  return ratio >= gear_min_ratio && ratio <= gear_max_ratio;
}

bool _valid(WireFormat f, List<int> p, {bool request = false}) {
  final n = p.length;
  switch (f) {
    case WireFormat.capabilities:
      return n == 5 && p[0] == capabilities_version;
    case WireFormat.ota_request:
      if (n == 0) return false;
      return switch (p[0]) {
        ota_begin => n == 37 && p.sublist(1, 5).any((v) => v != 0),
        ota_chunk => n > 5 && n <= secure_max_inner - 2,
        ota_finish || ota_abort => n == 1,
        _ => false,
      };
    case WireFormat.ota_reply:
      return n == 5 && p[0] <= ota_abort;
    case WireFormat.none:
      return false;
    case WireFormat.empty:
      return n == 0;
    case WireFormat.bool:
      return n == 1 && (!request || p[0] <= 1);
    case WireFormat.u16:
    case WireFormat.i16:
      return n == 2;
    case WireFormat.i32:
      return n == 4;
    case WireFormat.string:
      return !request || !p.contains(0);
    case WireFormat.row_index:
      return n == 1 && p[0] < power_table_rows;
    case WireFormat.power_table:
      return n == 1 + 2 * power_table_columns && p[0] < power_table_rows;
    case WireFormat.gear_index:
      return n == 0 || (n == 1 && p[0] < gear_max_count);
    case WireFormat.gear_write:
      if (n == 0 || p[0] > gear_max_count || p[0] == 1 || n != 1 + 2 * p[0])
        return false;
      final pairs = <int>{};
      for (var i = 0; i < p[0]; i++) {
        final pair = _u16(p, 1 + 2 * i);
        if (!_pair(pair) || !pairs.add(pair)) return false;
      }
      return true;
    case WireFormat.gear_reply:
      return (n == 1 || n == 4) &&
          p[0] <= gear_max_count &&
          p[0] != 1 &&
          (n == 1 || (p[1] < p[0] && _pair(_u16(p, 2))));
    case WireFormat.snapshot:
      return n >= snapshot_header_length - 2 &&
          p[0] == snapshot_version &&
          _u16(p, 3) > 0 &&
          _u16(p, 1) < _u16(p, 3);
    case WireFormat.scan:
      if (n < scan_header_length - 2 ||
          p[0] != scan_version ||
          p[1] > scan_end ||
          p[7] == 0 ||
          p[6] >= p[7])
        return false;
      return p[1] == scan_device ||
          (n == scan_header_length - 2 && p[6] == 0 && p[7] == 1);
  }
}

/// Low-level encoder for all registered commands. Validates direction and payload.
Uint8List encodeRequest(int operation, int id, [List<int> payload = const []]) {
  final c = command(id);
  if (operation != read && operation != write)
    throw ArgumentError.value(operation, 'operation');
  final f = operation == read ? c.readRequest : c.writeRequest;
  if (f == WireFormat.none)
    throw UnsupportedError('Operation not supported for ${c.name}');
  _bytes(payload);
  if (!_valid(f, payload, request: true))
    throw FormatException('Invalid ${f.name} request for ${c.name}');
  return Uint8List.fromList([operation, id, ...payload]);
}

void validateRequest(List<int> packet) {
  _bytes(packet);
  if (packet.length < 2) throw const FormatException('Truncated request');
  encodeRequest(packet[0], packet[1], packet.sublist(2));
}

Uint8List encodeRead(int id, {int? index}) =>
    encodeRequest(read, id, index == null ? const [] : [index]);
Uint8List encodeAction(int id) {
  if (command(id).writeRequest != WireFormat.empty)
    throw ArgumentError('Not an action');
  return encodeRequest(write, id);
}

Uint8List encodeScalarWrite(int id, int rawValue) {
  final f = command(id).writeRequest;
  final (min, max, width) = switch (f) {
    WireFormat.bool => (0, 1, 1),
    WireFormat.u16 => (0, 65535, 2),
    WireFormat.i16 => (-32768, 32767, 2),
    WireFormat.i32 => (-2147483648, 2147483647, 4),
    _ => throw ArgumentError('Not a scalar write'),
  };
  RangeError.checkValueInInterval(rawValue, min, max, 'rawValue');
  return encodeRequest(write, id, [
    for (var i = 0; i < width; i++) (rawValue >> (8 * i)) & 255,
  ]);
}

/// Engineering-unit convenience encoder. Rounds to the nearest wire unit,
/// ties away from zero. C callers use encode_scalar_write with explicit raw units.
Uint8List encodeValue(int id, Object value) {
  final c = command(id);
  if (c.writeRequest == WireFormat.string && value is String)
    return encodeRequest(write, id, utf8.encode(value));
  if (c.writeRequest == WireFormat.bool && value is bool)
    return encodeScalarWrite(id, value ? 1 : 0);
  if (value is num && value.isFinite)
    return encodeScalarWrite(id, (value * c.scale).round());
  throw ArgumentError('Value does not match command type');
}

Uint8List encodeGearTeeth(List<int> pairs) {
  for (final pair in pairs) {
    RangeError.checkValueInInterval(pair, 0, 65535, 'pair');
  }
  return encodeRequest(write, CommandId.gearTeeth, [
    pairs.length,
    for (final p in pairs) ...[p & 255, (p >> 8) & 255],
  ]);
}

Uint8List encodePowerTableRow(int row, List<int> positions) {
  for (final value in positions) {
    RangeError.checkValueInInterval(value, -32768, 32767, 'position');
  }
  return encodeRequest(write, CommandId.powerTableData, [
    row,
    for (final p in positions) ...[p & 255, (p >> 8) & 255],
  ]);
}

class ProtocolPacket {
  ProtocolPacket._(this.status, this.id, this.format, List<int> payload)
    : payload = List.unmodifiable(payload);
  final int status, id;
  final WireFormat format;
  final List<int> payload;
  bool get isError => status == error;
  int get rawValue => switch (format) {
    WireFormat.bool => payload[0] == 0 ? 0 : 1,
    WireFormat.u16 => _u16(payload, 0),
    WireFormat.i16 => _signed(_u16(payload, 0), 16),
    WireFormat.i32 => _signed(_u16(payload, 0) | (_u16(payload, 2) << 16), 32),
    _ => throw StateError('Not a scalar response'),
  };
  num get value => rawValue / command(id).scale;
  String get text {
    if (format != WireFormat.string) throw StateError('Not a string response');
    return utf8.decode(payload);
  }
}

/// Decodes one packet. Errors remain explicit objects, never a successful value.
/// Caller correlates the returned ID with the outstanding request. Context is
/// required because a logging write ACK is a boolean and a read reply is text.
ProtocolPacket decodeResponse(
  List<int> packet, {
  required ReplyKind kind,
  bool legacyBooleanEcho = false,
}) {
  _bytes(packet);
  if (packet.length < 2) throw const FormatException('Truncated response');
  final status = packet[0], id = packet[1];
  if (status == error)
    return ProtocolPacket._(status, id, WireFormat.none, packet.sublist(2));
  if (status != success) throw const FormatException('Unknown response status');
  final c = command(id);
  final f = switch (kind) {
    ReplyKind.read => c.readResponse,
    ReplyKind.write => c.writeResponse,
    ReplyKind.notification => c.notification,
  };
  if (f == WireFormat.none)
    throw UnsupportedError('Response not supported for ${c.name}');
  var payload = packet.sublist(2);
  if (legacyBooleanEcho &&
      kind == ReplyKind.write &&
      f == WireFormat.bool &&
      payload.length == 2 &&
      payload[1] == 0)
    payload = payload.sublist(0, 1);
  if (!_valid(f, payload)) throw FormatException('Invalid ${f.name} response');
  return ProtocolPacket._(status, id, f, payload);
}

/// Bounded snapshot assembly. A new request or disconnect must call reset().
/// There is no transfer ID on the wire; do not mix connections or overlapping requests.
class SnapshotAssembler {
  SnapshotAssembler({this.maxBytes = 1024 * 1024, this.maxChunks = 8192}) {
    if (maxBytes < 1 || maxChunks < 1)
      throw ArgumentError('Limits must be positive');
  }
  final int maxBytes, maxChunks;
  final Map<int, List<int>> _chunks = {};
  int? _count;
  int _bytesHeld = 0;
  void reset() {
    _chunks.clear();
    _count = null;
    _bytesHeld = 0;
  }

  Map<String, Object?>? add(List<int> packet) {
    try {
      final p = decodeResponse(packet, kind: ReplyKind.read);
      if (p.isError || p.format != WireFormat.snapshot)
        throw const FormatException('Not a snapshot');
      final index = _u16(p.payload, 1), count = _u16(p.payload, 3);
      if (count > maxChunks || (_count != null && _count != count))
        throw const FormatException('Inconsistent or excessive snapshot count');
      final bytes = p.payload.sublist(snapshot_header_length - 2);
      final previous = _chunks[index];
      if (previous != null) {
        if (previous.length != bytes.length ||
            List.generate(
              bytes.length,
              (i) => bytes[i] == previous[i],
            ).contains(false))
          throw const FormatException('Conflicting duplicate snapshot chunk');
      } else {
        if (_bytesHeld + bytes.length > maxBytes)
          throw const FormatException('Snapshot byte limit exceeded');
        _chunks[index] = bytes;
        _bytesHeld += bytes.length;
      }
      _count = count;
      if (_chunks.length < count) return null;
      final value = jsonDecode(
        utf8.decode([for (var i = 0; i < count; i++) ..._chunks[i]!]),
      );
      if (value is! Map<String, dynamic>)
        throw const FormatException('Snapshot must be an object');
      reset();
      return value;
    } catch (_) {
      reset();
      rethrow;
    }
  }
}

/// Packet-level scan view; transport/session code owns fragment assembly and timeout.
class ScanFragment {
  ScanFragment(List<int> packet)
    : _packet = decodeResponse(packet, kind: ReplyKind.notification) {
    if (_packet.isError || _packet.format != WireFormat.scan)
      throw const FormatException('Not a scan fragment');
  }
  final ProtocolPacket _packet;
  int get event => _packet.payload[1];
  int get scanId => _u16(_packet.payload, 2);
  int get sequence => _u16(_packet.payload, 4);
  int get index => _packet.payload[6];
  int get count => _packet.payload[7];
  List<int> get body => _packet.payload.sublist(scan_header_length - 2);
  static ({String uuid, String name}) decodeDeviceBody(List<int> body) {
    _bytes(body);
    if (body.isEmpty || body[0] == 0 || body[0] + 1 > body.length)
      throw const FormatException('Invalid scan device body');
    return (
      uuid: utf8.decode(body.sublist(1, body[0] + 1)),
      name: utf8.decode(body.sublist(body[0] + 1)),
    );
  }
}

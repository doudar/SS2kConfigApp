import 'dart:convert';

const int settingsSnapshotReference = 0x31;
const int settingsSnapshotVersion = 1;
const int settingsSnapshotHeaderLength = 7;

enum SettingsSnapshotRequestResult { supported, unsupported }

/// Uses individual reads only when the snapshot request explicitly reports
/// that the firmware does not support 0x31. Errors deliberately propagate.
Future<SettingsSnapshotRequestResult> requestSettingsWithSnapshotFallback({
  required Future<SettingsSnapshotRequestResult> Function() requestSnapshot,
  required Future<void> Function() requestIndividually,
}) async {
  final result = await requestSnapshot();
  if (result == SettingsSnapshotRequestResult.unsupported) {
    await requestIndividually();
  }
  return result;
}

bool isUnsupportedSettingsSnapshotPacket(List<int> packet) =>
    packet.length >= 2 &&
    packet[0] == 0xff &&
    packet[1] == settingsSnapshotReference;

/// Reassembles the versioned, chunked JSON returned by custom-characteristic
/// read `0x01, 0x31`.
class SettingsSnapshotDecoder {
  final Map<int, List<int>> _chunks = <int, List<int>>{};
  int? _chunkCount;

  int get receivedChunkCount => _chunks.length;
  int? get expectedChunkCount => _chunkCount;

  void reset() {
    _chunks.clear();
    _chunkCount = null;
  }

  /// Returns the decoded snapshot only after every chunk has arrived.
  ///
  /// Chunks may arrive out of order. Duplicate chunks are accepted when their
  /// contents match, while inconsistent framing is rejected rather than
  /// applying a partial or mixed snapshot.
  Map<String, dynamic>? add(List<int> packet) {
    if (packet.length < settingsSnapshotHeaderLength) {
      throw const FormatException('Settings snapshot chunk is too short.');
    }
    if (packet[0] != 0x80 || packet[1] != settingsSnapshotReference) {
      throw const FormatException('Not a settings snapshot chunk.');
    }
    if (packet[2] != settingsSnapshotVersion) {
      throw FormatException(
        'Unsupported settings snapshot version ${packet[2]}.',
      );
    }

    final chunk = packet[3] | (packet[4] << 8);
    final chunkCount = packet[5] | (packet[6] << 8);
    if (chunkCount == 0 || chunk >= chunkCount) {
      throw const FormatException('Invalid settings snapshot chunk index.');
    }
    if (_chunkCount != null && _chunkCount != chunkCount) {
      throw const FormatException('Settings snapshot chunk count changed.');
    }
    _chunkCount = chunkCount;

    final payload = List<int>.unmodifiable(
      packet.sublist(settingsSnapshotHeaderLength),
    );
    final previous = _chunks[chunk];
    if (previous != null && !_sameBytes(previous, payload)) {
      throw FormatException('Settings snapshot chunk $chunk changed.');
    }
    _chunks[chunk] = payload;

    if (_chunks.length != chunkCount) return null;

    final bytes = <int>[
      for (var index = 0; index < chunkCount; index++) ...?_chunks[index],
    ];
    if (bytes.length !=
        _chunks.values.fold<int>(0, (sum, c) => sum + c.length)) {
      throw const FormatException('Settings snapshot is missing a chunk.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Settings snapshot must be a JSON object.');
    }

    final result = <String, dynamic>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
    reset();
    return result;
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

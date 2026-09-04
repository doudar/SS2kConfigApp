import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

const int bleScanResultsReference = 0x32;
const int bleScanResultsVersion = 1;
const int bleScanResultsHeaderLength = 10;

enum BleScanResultEvent { begin, device, end }

class BleScanDevice {
  const BleScanDevice({required this.name, required this.uuid, this.address});

  final String name;
  final String uuid;
  final String? address;
}

class BleScanResultUpdate {
  const BleScanResultUpdate({
    required this.event,
    required this.devices,
    required this.changed,
    this.isComplete,
  });

  final BleScanResultEvent event;
  final List<BleScanDevice> devices;
  final bool changed;
  final bool? isComplete;
}

class _FragmentAssembly {
  _FragmentAssembly(int count)
    : fragments = List<Uint8List?>.filled(count, null);

  final List<Uint8List?> fragments;

  bool get complete => fragments.every((fragment) => fragment != null);
}

/// Reassembles the versioned, per-device scan stream emitted by current
/// SmartSpin2k firmware. Older firmware never sends reference 0x32, allowing
/// callers to keep consuming the legacy BLE_foundDevices JSON unchanged.
class BleScanResultStreamDecoder {
  int? _scanId;
  bool _active = false;
  final SplayTreeMap<int, BleScanDevice> _scanDevices = SplayTreeMap();
  final Map<String, BleScanDevice> _devices = {};
  final Map<int, _FragmentAssembly> _fragments = {};

  List<BleScanDevice> get devices => List.unmodifiable(_devices.values);

  /// Clears discoveries when the SmartSpin2k connection that produced them
  /// closes. A new scan on the same connection deliberately does not clear the
  /// list: nearby sensors can disappear from an individual scan cycle while
  /// still being valid choices for the user.
  void reset() {
    _scanId = null;
    _active = false;
    _scanDevices.clear();
    _devices.clear();
    _fragments.clear();
  }

  BleScanResultUpdate? add(List<int> packet) {
    if (packet.length < bleScanResultsHeaderLength ||
        packet[0] != 0x80 ||
        packet[1] != bleScanResultsReference ||
        packet[2] != bleScanResultsVersion) {
      return null;
    }

    final eventValue = packet[3];
    if (eventValue >= BleScanResultEvent.values.length) return null;
    final event = BleScanResultEvent.values[eventValue];
    final scanId = packet[4] | (packet[5] << 8);
    final sequence = packet[6] | (packet[7] << 8);
    final fragment = packet[8];
    final fragmentCount = packet[9];
    if (fragmentCount == 0 || fragment >= fragmentCount) return null;

    if (event == BleScanResultEvent.begin) {
      _scanId = scanId;
      _active = true;
      _scanDevices.clear();
      _fragments.clear();
      return BleScanResultUpdate(
        event: event,
        devices: devices,
        changed: false,
      );
    }

    if (!_active || scanId != _scanId) return null;

    if (event == BleScanResultEvent.end) {
      final complete =
          _fragments.isEmpty &&
          _scanDevices.length == sequence &&
          Iterable<int>.generate(sequence).every(_scanDevices.containsKey);
      _active = false;
      return BleScanResultUpdate(
        event: event,
        devices: devices,
        changed: false,
        isComplete: complete,
      );
    }

    final assembly = _fragments.putIfAbsent(
      sequence,
      () => _FragmentAssembly(fragmentCount),
    );
    if (assembly.fragments.length != fragmentCount) {
      _fragments.remove(sequence);
      return null;
    }
    assembly.fragments[fragment] = Uint8List.fromList(
      packet.sublist(bleScanResultsHeaderLength),
    );
    if (!assembly.complete) {
      return BleScanResultUpdate(
        event: event,
        devices: devices,
        changed: false,
      );
    }

    final body = BytesBuilder(copy: false);
    for (final bytes in assembly.fragments) {
      body.add(bytes!);
    }
    _fragments.remove(sequence);
    final record = body.takeBytes();
    if (record.isEmpty) return null;
    final uuidLength = record[0];
    if (uuidLength == 0 || 1 + uuidLength > record.length) return null;

    try {
      final uuid = utf8.decode(record.sublist(1, 1 + uuidLength));
      final name = utf8.decode(record.sublist(1 + uuidLength));
      final device = BleScanDevice(name: name, uuid: uuid);
      _scanDevices[sequence] = device;
      final key = '$uuid\u0000$name';
      final changed = !_devices.containsKey(key);
      _devices[key] = device;
      return BleScanResultUpdate(
        event: event,
        devices: devices,
        changed: changed,
      );
    } on FormatException {
      return null;
    }
  }
}

/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_scan_results_protocol.dart';
import 'ble_sensor_services.dart';

/// A BLE sensor discovered by the companion app before it connects to a
/// SmartSpin2k.
class NearbyBleDevice {
  const NearbyBleDevice({
    required this.name,
    required this.uuid,
    required this.remoteId,
    required this.identitySuffix,
  });

  final String name;
  final String uuid;
  final String remoteId;
  final String? identitySuffix;

  BleScanDevice get scanDevice =>
      BleScanDevice(name: name, uuid: uuid, address: remoteId);
}

/// Process-local discoveries collected while the app scans for SmartSpin2ks.
///
/// Native SmartSpin2k discovery is intentionally an unfiltered BLE scan. That
/// means the app has already received most of the advertisements the firmware
/// will later find. Keeping the supported ones here lets a newly connected
/// SmartSpin2k show useful picker choices immediately, while its own scan can
/// still add to or correct the list.
class NearbyBleDevices {
  NearbyBleDevices._();

  static final NearbyBleDevices instance = NearbyBleDevices._();

  final Map<String, _NearbyBlePeer> _peersByRemoteId = {};
  final Map<String, BleScanDevice> _firmwareDevices = {};

  List<NearbyBleDevice> get devices {
    // A private address can rotate during a long app session. Collapse exact
    // generated-name repeats without interpreting abbreviations.
    final byName = <String, NearbyBleDevice>{};
    for (final peer in _peersByRemoteId.values) {
      final device = peer.firmwareChoice ?? peer.latest;
      if (device == null) continue;
      final key = device.name.toLowerCase();
      byName.putIfAbsent(key, () => device);
    }
    return List.unmodifiable(byName.values);
  }

  void observeAll(Iterable<ScanResult> results) {
    for (final result in results) {
      observe(result);
    }
  }

  void observe(ScanResult result) {
    final device = fromScanResult(result);
    if (device == null) return;

    // Preserve every exact name observed for this physical peer. A later
    // SmartSpin2k result can use any one of those names to recover the address
    // and replace all aliases without guessing what an abbreviation means.
    final key = device.remoteId.toLowerCase();
    final peer = _peersByRemoteId.putIfAbsent(
      key,
      () => _NearbyBlePeer(device.remoteId),
    );
    peer.latest = device;
    peer.observations[_deviceKey(device.name, device.uuid)] = device;
    _reconcileFirmwareChoices();
  }

  /// Attaches a phone-visible address to a firmware result when one and only
  /// one local BLE peer can be identified safely.
  ///
  /// Exact names win. When the advertisement and scan-response names differ,
  /// the firmware-generated suffix can still identify the peer, provided the
  /// suffix is unique within the same sensor category.
  ///
  /// The returned name and UUID are always the firmware values. If no safe
  /// match exists, [address] remains null and callers retain both entries.
  BleScanDevice reconcileFirmwareDevice(BleScanDevice device) {
    _firmwareDevices[_deviceKey(device.name, device.uuid)] = device;
    _reconcileFirmwareChoices();

    final matches = _matchingPeerGroups(device);
    if (matches.length != 1) return device;
    return BleScanDevice(
      name: device.name,
      uuid: device.uuid,
      address: matches.single.peers.first.remoteId,
    );
  }

  Iterable<BleScanDevice> scanDevicesFor(BluetoothDevice smartSpin) sync* {
    final connectedId = smartSpin.remoteId.str.toLowerCase();
    final emitted = <String>{};
    for (final device in devices) {
      // The phone can hear the SmartSpin2k it is about to connect to, whereas
      // that SmartSpin2k cannot discover itself during its firmware scan.
      if (device.remoteId.toLowerCase() == connectedId) continue;
      emitted.add(_deviceKey(device.name, device.uuid));
      yield device.scanDevice;
    }

    // Apple platforms do not expose a BLE address, so their native results
    // cannot safely reproduce adevName and are excluded above. Firmware
    // discoveries are already authoritative generated names, however, and can
    // safely seed this and future SmartSpin2k connections without an address.
    for (final firmwareDevice in _firmwareDevices.values) {
      // A uniquely reconciled firmware record is already represented by its
      // phone-visible peer above. Do not emit it a second time without an
      // address.
      if (_matchingPeerGroups(firmwareDevice).length == 1) continue;
      final key = _deviceKey(firmwareDevice.name, firmwareDevice.uuid);
      if (!emitted.add(key)) continue;
      yield firmwareDevice;
    }
  }

  /// Converts one Flutter scan result using the firmware's service-selection
  /// and `adevName2UniqueName` rules.
  static NearbyBleDevice? fromScanResult(ScanResult result) {
    final advertisement = result.advertisementData;
    final remoteId = result.device.remoteId.str.trim();
    final name = firmwareCompatibleName(
      advertisedName: advertisement.advName,
      remoteId: remoteId,
      manufacturerData: advertisement.manufacturerData,
    );
    if (name == null) return null;
    final identitySuffix = _firmwareIdentitySuffix(
      advertisedName: advertisement.advName,
      remoteId: remoteId,
      manufacturerData: advertisement.manufacturerData,
    );

    final advertisedServices = advertisement.serviceUuids
        .map((uuid) => _shortUuid(uuid.str))
        .toSet();

    BleSensorServiceDefinition? match;
    for (final supported in supportedBleSensorServices) {
      if (!advertisedServices.contains(supported.advertisedUuid)) continue;
      if (supported.requiredName != null && name != supported.requiredName) {
        continue;
      }
      match = supported;
      break;
    }
    if (match == null) return null;

    // Firmware treats FTMS as the primary service even if a service earlier in
    // SUPPORTED_SERVICES matched first (the IC4 compatibility workaround).
    final uuid = advertisedServices.contains(bleFitnessMachineServiceUuid)
        ? bleFitnessMachineDeviceUuid
        : match.deviceUuid;
    return NearbyBleDevice(
      name: name,
      uuid: uuid,
      remoteId: remoteId,
      identitySuffix: identitySuffix,
    );
  }

  /// Reproduces the current firmware's `adevName2UniqueName` output.
  ///
  /// Flutter exposes the peer MAC on Android and several desktop platforms.
  /// Apple platforms expose an opaque UUID instead, so an exact firmware name
  /// cannot be derived there; returning null avoids offering a value the
  /// SmartSpin2k would never be able to match.
  static String? firmwareCompatibleName({
    required String advertisedName,
    required String remoteId,
    required Map<int, List<int>> manufacturerData,
  }) {
    final address = remoteId.toLowerCase();
    final match = RegExp(
      r'^([0-9a-f]{2}):(?:[0-9a-f]{2}:){4}([0-9a-f]{2})$',
    ).firstMatch(address);
    if (match == null) return null;

    final cleanName = advertisedName.trim();
    if (cleanName.isEmpty) return address;

    final firstByte = int.parse(match.group(1)!, radix: 16);
    final privateRandom =
        (firstByte & 0xc0) == 0x40 || (firstByte & 0xc0) == 0x00;
    if (!privateRandom) return '$cleanName ${match.group(2)}';

    if (manufacturerData.isNotEmpty) {
      final entry = manufacturerData.entries.first;
      // Flutter separates the two-byte company identifier from its payload;
      // NimBLE includes it in the manufacturer field. The last payload byte is
      // identical. If the payload is empty, reconstruct NimBLE's final company
      // identifier byte (Bluetooth company IDs are little-endian on the air).
      final suffix = entry.value.isNotEmpty
          ? entry.value.last
          : (entry.key >> 8) & 0xff;
      return '$cleanName ${suffix.toRadixString(16).padLeft(2, '0')}';
    }
    return cleanName;
  }

  static String? _firmwareIdentitySuffix({
    required String advertisedName,
    required String remoteId,
    required Map<int, List<int>> manufacturerData,
  }) {
    if (advertisedName.trim().isEmpty) return null;
    final match = RegExp(
      r'^([0-9a-f]{2}):(?:[0-9a-f]{2}:){4}([0-9a-f]{2})$',
    ).firstMatch(remoteId.toLowerCase());
    if (match == null) return null;

    final firstByte = int.parse(match.group(1)!, radix: 16);
    final privateRandom =
        (firstByte & 0xc0) == 0x40 || (firstByte & 0xc0) == 0x00;
    if (!privateRandom) return match.group(2);
    if (manufacturerData.isEmpty) return null;

    final entry = manufacturerData.entries.first;
    final suffix = entry.value.isNotEmpty
        ? entry.value.last
        : (entry.key >> 8) & 0xff;
    return suffix.toRadixString(16).padLeft(2, '0');
  }

  static String _shortUuid(String uuid) {
    final value = uuid.toLowerCase();
    final bluetoothBase = RegExp(
      r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$',
    ).firstMatch(value);
    return bluetoothBase?.group(1) ?? value.replaceFirst(RegExp(r'^0x'), '');
  }

  void _reconcileFirmwareChoices() {
    for (final peer in _peersByRemoteId.values) {
      peer.firmwareChoice = null;
    }
    for (final firmwareDevice in _firmwareDevices.values) {
      final matches = _matchingPeerGroups(firmwareDevice);
      if (matches.length != 1) continue;
      // A private address can rotate while the app remains open. Apply the
      // authoritative firmware name to every address that produced the same
      // generated native name so the aliases remain collapsed in [devices].
      for (final peer in matches.single.peers) {
        peer.firmwareChoice = NearbyBleDevice(
          name: firmwareDevice.name,
          uuid: firmwareDevice.uuid,
          remoteId: peer.remoteId,
          identitySuffix: _suffixFromFirmwareName(firmwareDevice.name),
        );
      }
    }
  }

  List<_NearbyBlePeerGroup> _matchingPeerGroups(BleScanDevice firmwareDevice) {
    final firmwareName = firmwareDevice.name.toLowerCase();
    final categoryPeers = <_NearbyBlePeerMatch>[];
    final exactPeers = <_NearbyBlePeerMatch>[];
    for (final peer in _peersByRemoteId.values) {
      final observations = peer.observations.values
          .where(
            (observed) =>
                _sameDeviceCategory(observed.uuid, firmwareDevice.uuid),
          )
          .toList(growable: false);
      if (observations.isEmpty) continue;
      categoryPeers.add(_NearbyBlePeerMatch(peer, observations));
      final exactObservations = observations
          .where((observed) => observed.name.toLowerCase() == firmwareName)
          .toList(growable: false);
      if (exactObservations.isNotEmpty) {
        exactPeers.add(_NearbyBlePeerMatch(peer, exactObservations));
      }
    }

    if (exactPeers.isNotEmpty) {
      return _groupEquivalentPeers(exactPeers);
    }

    final firmwareSuffix = _suffixFromFirmwareName(firmwareDevice.name);
    if (firmwareSuffix == null) return const [];
    final suffixPeers = <_NearbyBlePeerMatch>[];
    for (final match in categoryPeers) {
      final matchingObservations = match.observations
          .where((observed) => observed.identitySuffix == firmwareSuffix)
          .toList(growable: false);
      if (matchingObservations.isNotEmpty) {
        suffixPeers.add(_NearbyBlePeerMatch(match.peer, matchingObservations));
      }
    }
    return _groupEquivalentPeers(suffixPeers);
  }

  /// Groups observations that have the same generated native name. Windows
  /// and Android can expose more than one private address for one physical
  /// sensor over the lifetime of the app, but those observations still carry
  /// the same firmware identity suffix. Different names sharing only an
  /// eight-bit suffix remain separate and therefore ambiguous.
  static List<_NearbyBlePeerGroup> _groupEquivalentPeers(
    List<_NearbyBlePeerMatch> matches,
  ) {
    final groups = <_NearbyBlePeerGroup>[];
    for (final match in matches) {
      final names = match.observations
          .map((observed) => observed.name.toLowerCase())
          .toSet();
      final overlapping = groups
          .where((group) => group.names.any(names.contains))
          .toList(growable: false);
      if (overlapping.isEmpty) {
        groups.add(_NearbyBlePeerGroup([match.peer], names));
        continue;
      }

      final target = overlapping.first;
      target.peers.add(match.peer);
      target.names.addAll(names);
      for (final duplicate in overlapping.skip(1)) {
        target.peers.addAll(duplicate.peers);
        target.names.addAll(duplicate.names);
        groups.remove(duplicate);
      }
    }
    return groups;
  }

  static String? _suffixFromFirmwareName(String name) {
    final match = RegExp(r'(?:^|\s)([0-9a-fA-F]{2})$').firstMatch(name.trim());
    return match?.group(1)?.toLowerCase();
  }

  static bool _sameDeviceCategory(String first, String second) {
    if (isHeartRateDeviceServiceUuid(first) &&
        isHeartRateDeviceServiceUuid(second)) {
      return true;
    }
    if (isPowerMeterDeviceServiceUuid(first) &&
        isPowerMeterDeviceServiceUuid(second)) {
      return true;
    }
    return first.toLowerCase() == second.toLowerCase();
  }

  static String _deviceKey(String name, String uuid) =>
      '${uuid.toLowerCase()}\u0000${name.toLowerCase()}';

  void clear() {
    _peersByRemoteId.clear();
    _firmwareDevices.clear();
  }
}

class _NearbyBlePeer {
  _NearbyBlePeer(this.remoteId);

  final String remoteId;
  final Map<String, NearbyBleDevice> observations = {};
  NearbyBleDevice? latest;
  NearbyBleDevice? firmwareChoice;
}

class _NearbyBlePeerMatch {
  const _NearbyBlePeerMatch(this.peer, this.observations);

  final _NearbyBlePeer peer;
  final List<NearbyBleDevice> observations;
}

class _NearbyBlePeerGroup {
  _NearbyBlePeerGroup(this.peers, this.names);

  final List<_NearbyBlePeer> peers;
  final Set<String> names;
}

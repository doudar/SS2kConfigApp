import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'constants.dart';
import 'dircon_discovery.dart';
import 'smartspin_advertisement.dart';

class SmartSpinScanResult {
  const SmartSpinScanResult({this.ble, this.network, this.connectedIdentity})
    : assert(ble != null || network != null);

  final ScanResult? ble;
  final DirConEndpoint? network;

  /// Preserve the handle of an already-open session when a later scan discovers
  /// the other transport. Opening its tile must not create a second session.
  final BluetoothDevice? connectedIdentity;
  BluetoothDevice get device =>
      connectedIdentity ??
      ble?.device ??
      BluetoothDevice.fromId('mdns:${network!.id}');
  String get name =>
      network?.name ??
      (ble!.advertisementData.advName.isNotEmpty
          ? ble!.advertisementData.advName
          : ble!.device.platformName);
  String? get host =>
      network?.host ??
      (isSmartSpin
          ? SmartSpinAdvertisement.ipAddress(
              ble?.advertisementData.manufacturerData ?? {},
            )
          : null);
  bool get isSmartSpin =>
      network?.isSmartSpin ??
      (ble?.advertisementData.serviceUuids.contains(Guid(csUUID)) ?? false);
  bool get connectable => network != null || ble!.advertisementData.connectable;

  static List<SmartSpinScanResult> merge(
    List<ScanResult> bluetooth,
    List<DirConEndpoint> network, {
    bool includeAllBle = false,
    bool includeFtms = false,
  }) {
    final devices = {
      for (final result in bluetooth) result.device.remoteId: result,
    }.values;
    // Only SmartSpin2k advertisements can identify a SmartSpin2k network
    // endpoint. A third-party trainer may have the same display name.
    final ble = devices
        .where(
          (result) =>
              (includeAllBle && !includeFtms) ||
              result.advertisementData.serviceUuids.contains(Guid(csUUID)),
        )
        .toList();
    final endpoints = {
      for (final endpoint in network)
        if (includeFtms || endpoint.isSmartSpin) endpoint.id: endpoint,
    }.values.toList();
    final matched = <ScanResult>{};
    final results = <SmartSpinScanResult>[];
    for (final endpoint in endpoints) {
      if (!endpoint.isSmartSpin) {
        results.add(SmartSpinScanResult(network: endpoint));
        continue;
      }
      final exact = ble
          .where(
            (result) =>
                !matched.contains(result) &&
                SmartSpinAdvertisement.ipAddress(
                      result.advertisementData.manufacturerData,
                    ) ==
                    endpoint.host,
          )
          .toList();
      ScanResult? match = exact.length == 1 ? exact.single : null;
      // Older firmware has no advertised IP; Apple BLE identifiers are opaque.
      // Only use an unambiguous name, never override a conflicting advertised IP.
      if (match == null &&
          endpoints
                  .where(
                    (e) => e.name.toLowerCase() == endpoint.name.toLowerCase(),
                  )
                  .length ==
              1) {
        final sameName = ble
            .where(
              (result) =>
                  !matched.contains(result) &&
                  (result.advertisementData.advName.isNotEmpty
                              ? result.advertisementData.advName
                              : result.device.platformName)
                          .toLowerCase() ==
                      endpoint.name.toLowerCase(),
            )
            .toList();
        if (sameName.length == 1 &&
            SmartSpinAdvertisement.ipAddress(
                  sameName.single.advertisementData.manufacturerData,
                ) ==
                null) {
          match = sameName.single;
        }
      }
      if (match != null) matched.add(match);
      results.add(SmartSpinScanResult(ble: match, network: endpoint));
    }
    results.addAll(
      ble
          .where((r) => !matched.contains(r))
          .map((r) => SmartSpinScanResult(ble: r)),
    );
    if (includeFtms) {
      final ftms = Guid(ftmsServiceUUID);
      results.addAll(
        devices
            .where(
              (r) =>
                  !ble.contains(r) &&
                  (includeAllBle ||
                      r.advertisementData.serviceUuids.contains(ftms) ||
                      r.advertisementData.serviceData.containsKey(ftms)),
            )
            .map((r) => SmartSpinScanResult(ble: r)),
      );
    }
    return results;
  }
}

class SmartSpinAdvertisementData {
  const SmartSpinAdvertisementData({required this.ipAddress});

  /// Null means the device is advertising but does not currently have a
  /// usable WiFi address (0.0.0.0 or 255.255.255.255).
  final String? ipAddress;
}

class SmartSpinAdvertisement {
  static const int manufacturerId = 0xffff;
  static const int version = 1;

  static String? ipAddress(Map<int, List<int>> manufacturerData) {
    return parse(manufacturerData)?.ipAddress;
  }

  static SmartSpinAdvertisementData? parse(
    Map<int, List<int>> manufacturerData,
  ) {
    for (final entry in manufacturerData.entries) {
      var payload = entry.value;
      if (payload.length >= 9 && payload[0] == 0xff && payload[1] == 0xff) {
        payload = payload.sublist(2);
      } else if (entry.key != manufacturerId) {
        continue;
      }

      if (payload.length < 7 ||
          payload[0] != 0x53 ||
          payload[1] != 0x53 ||
          payload[2] != version) {
        continue;
      }

      final octets = payload.sublist(3, 7);
      if (octets.every((octet) => octet == 0) ||
          octets.every((octet) => octet == 255)) {
        return const SmartSpinAdvertisementData(ipAddress: null);
      }
      return SmartSpinAdvertisementData(ipAddress: octets.join('.'));
    }
    return null;
  }
}

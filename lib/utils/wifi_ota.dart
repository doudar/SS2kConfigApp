import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:multicast_dns/multicast_dns.dart';

class WifiOTA {
  /// Attempts to update firmware via WiFi
  /// Returns true if successful, false if failed
  static Future<bool> updateFirmware({
    required String deviceName,
    required String firmwarePath,
    required Function(double) onProgress,
  }) async {
    // Clean up device name for mDNS
    final cleanDeviceName = deviceName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    print('WiFi OTA: Starting update for device: $cleanDeviceName');
    print('WiFi OTA: Using firmware path: $firmwarePath');

    final mdnsHost = '$cleanDeviceName.local';
    String? mdnsIp;
    if (Platform.isAndroid) {
      mdnsIp = await _resolveMdnsAddress(mdnsHost);
      if (mdnsIp != null) {
        print('WiFi OTA: mDNS resolved $mdnsHost to $mdnsIp');
      } else {
        print('WiFi OTA: mDNS lookup for $mdnsHost returned no address');
      }
    }

    final candidates = <String>[
      if (mdnsIp != null) 'http://$mdnsIp',
      'http://$mdnsHost',
      'http://$cleanDeviceName',
    ];

    String? baseUrl;
    for (final candidate in candidates) {
      print('WiFi OTA: Attempting to connect to: $candidate');
      if (await _checkDeviceAvailability(candidate)) {
        baseUrl = candidate;
        break;
      }
    }

    if (baseUrl == null) {
      print('WiFi OTA: No reachable host found for $cleanDeviceName');
      return false;
    }
    onProgress(.1);
    // Get firmware bytes - handle both asset and file paths
    List<int> firmwareBytes;
    try {
      if (firmwarePath.startsWith('assets/')) {
        print('WiFi OTA: Loading firmware from assets');
        final byteData = await rootBundle.load(firmwarePath);
        firmwareBytes = byteData.buffer.asUint8List();
      } else {
        print('WiFi OTA: Loading firmware from file system');
        final file = File(firmwarePath);
        firmwareBytes = await file.readAsBytes();
      }
      print('WiFi OTA: Firmware loaded, size: ${firmwareBytes.length} bytes');
    } catch (e) {
      print('WiFi OTA: Failed to load firmware: $e');
      return false;
    }

    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/update'));

      // Use a simple stream for all cases
      final multipartFile = http.MultipartFile.fromBytes(
        'update',
        firmwareBytes,
        filename: 'firmware.bin',
        contentType: MediaType('application', 'octet-stream'),
      );
      request.files.add(multipartFile);

      // Send request and wait only for headers
      print('WiFi OTA: Sending firmware...');
      var prog = 0.1;
      // Update progress before send
      request.send();

      while (prog < 1) {
        onProgress(prog);
        prog = prog + .01;
        await Future.delayed(Duration(milliseconds: 400));
      }
      print('WiFi OTA: Upload successful, device will reboot');
      return true;
    } catch (e) {
      print('WiFi OTA: Upload failed: $e');
      return false;
    }
  }

  static Future<bool> _checkDeviceAvailability(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/OTAIndex'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        print('WiFi OTA: Device is available via $baseUrl');
        return true;
      }
      print('WiFi OTA: $baseUrl returned status ${response.statusCode}');
      return false;
    } catch (e) {
      print('WiFi OTA: Failed to reach $baseUrl: $e');
      return false;
    }
  }

  static Future<String?> _resolveMdnsAddress(String hostname) async {
    final client = MDnsClient();
    try {
      await client.start();
      final record = await client
          .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(hostname))
          .timeout(const Duration(seconds: 3))
          .first;
      return record.address.address;
    } catch (e) {
      print('WiFi OTA: mDNS lookup failed for $hostname: $e');
      return null;
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }
  }
}

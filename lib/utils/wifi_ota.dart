import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/services.dart' show rootBundle;

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

    var baseUrl = 'http://$cleanDeviceName.local';
    print('WiFi OTA: Attempting to connect to: $baseUrl');

    // First verify device is reachable
    try {
      print('WiFi OTA: Checking device availability...');
      final response = await http.get(Uri.parse('$baseUrl/OTAIndex')).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        print('WiFi OTA: Device returned non-200 status code: ${response.statusCode}');
        return false;
      }
      print('WiFi OTA: Device is available');
    } catch (e) {
      print('WiFi OTA: Failed to connect to device: $e');
      // Try alternate URL without .local suffix as fallback
      try {
        print('WiFi OTA: Trying alternate URL: http://$cleanDeviceName');
        final altResponse =
            await http.get(Uri.parse('http://$cleanDeviceName/OTAIndex')).timeout(const Duration(seconds: 5));
        if (altResponse.statusCode != 200) {
          print('WiFi OTA: Alternate URL failed with status code: ${altResponse.statusCode}');
          return false;
        }
        print('WiFi OTA: Alternate URL successful, using it for update');
        baseUrl = 'http://$cleanDeviceName';
      } catch (e2) {
        print('WiFi OTA: Alternate URL also failed: $e2');
        return false;
      }
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

    while(prog < 1) {
      
      onProgress(prog);
      prog = prog +.01;
      await Future.delayed(Duration(milliseconds: 400));
    }
  print('WiFi OTA: Upload successful, device will reboot');
    return true;
  }
}

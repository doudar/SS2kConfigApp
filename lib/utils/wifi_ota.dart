import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:multicast_dns/multicast_dns.dart';

enum WifiOtaPhase {
  locatingDevice,
  loadingFirmware,
  uploading,
  processing,
  accepted,
}

class WifiOtaProgress {
  const WifiOtaProgress({
    required this.phase,
    required this.message,
    this.fraction,
    this.bytesSent,
    this.totalBytes,
  });

  final WifiOtaPhase phase;
  final String message;
  final double? fraction;
  final int? bytesSent;
  final int? totalBytes;
}

enum WifiOtaOutcome { accepted, unavailable, rejected, failed }

class WifiOtaResult {
  const WifiOtaResult({
    required this.outcome,
    required this.message,
    this.statusCode,
  });

  final WifiOtaOutcome outcome;
  final String message;
  final int? statusCode;

  bool get accepted => outcome == WifiOtaOutcome.accepted;
  bool get shouldFallBackToBluetooth => outcome == WifiOtaOutcome.unavailable;
}

/// Multipart request that reports the bytes actually written to the socket.
class ProgressMultipartRequest extends http.MultipartRequest {
  ProgressMultipartRequest(
    super.method,
    super.url, {
    required this.onUploadProgress,
  });

  final void Function(int bytesSent, int totalBytes) onUploadProgress;

  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            sent += chunk.length;
            onUploadProgress(sent, total);
            sink.add(chunk);
          },
        ),
      ),
    );
  }
}

class WifiOTA {
  static const Duration endpointStageTimeout = Duration(seconds: 10);

  /// Attempts to update firmware via WiFi
  static Future<WifiOtaResult> updateFirmware({
    required String deviceName,
    String? deviceIp,
    required String firmwarePath,
    required String firmwareFilename,
    required void Function(WifiOtaProgress progress) onProgress,
    http.Client? client,
    Duration endpointTimeout = endpointStageTimeout,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    // Clean up device name for mDNS
    final cleanDeviceName = deviceName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim();
    print('WiFi OTA: Starting update for device: $cleanDeviceName');
    print('WiFi OTA: Using firmware path: $firmwarePath');
    onProgress(
      const WifiOtaProgress(
        phase: WifiOtaPhase.locatingDevice,
        message: 'Locating SmartSpin2k on WiFi…',
        fraction: 0,
      ),
    );

    try {
      String? baseUrl;
      if (deviceIp != null && deviceIp.isNotEmpty) {
        final ipBaseUrl = 'http://$deviceIp';
        print('WiFi OTA: Checking advertised IP: $ipBaseUrl');
        onProgress(
          WifiOtaProgress(
            phase: WifiOtaPhase.locatingDevice,
            message: 'Checking advertised IP $deviceIp…',
            fraction: 0,
          ),
        );
        if (await _checkDeviceAvailability(
          httpClient,
          ipBaseUrl,
          timeout: endpointTimeout,
        )) {
          baseUrl = ipBaseUrl;
        }
      }

      if (baseUrl == null) {
        final mdnsHost = '$cleanDeviceName.local';
        print('WiFi OTA: Advertised IP unavailable; checking mDNS $mdnsHost');
        onProgress(
          WifiOtaProgress(
            phase: WifiOtaPhase.locatingDevice,
            message: 'Checking mDNS $mdnsHost…',
            fraction: 0,
          ),
        );
        baseUrl = await _locateWithMdns(
          httpClient,
          mdnsHost,
          endpointTimeout,
        ).timeout(endpointTimeout, onTimeout: () => null);
      }

      if (baseUrl == null) {
        final message = 'SmartSpin2k was not reachable over WiFi.';
        print('WiFi OTA: No reachable host found for $cleanDeviceName');
        return WifiOtaResult(
          outcome: WifiOtaOutcome.unavailable,
          message: message,
        );
      }
      onProgress(
        const WifiOtaProgress(
          phase: WifiOtaPhase.loadingFirmware,
          message: 'Preparing firmware image…',
          fraction: 0,
        ),
      );

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
      } catch (error) {
        final message = 'Could not read the firmware image: $error';
        print('WiFi OTA: $message');
        return WifiOtaResult(outcome: WifiOtaOutcome.failed, message: message);
      }

      // Create multipart request
      late ProgressMultipartRequest request;
      request = ProgressMultipartRequest(
        'POST',
        Uri.parse('$baseUrl/update'),
        onUploadProgress: (sent, total) {
          final fraction = total == 0 ? 0.0 : (sent / total).clamp(0.0, 1.0);
          final finished = sent >= total;
          onProgress(
            WifiOtaProgress(
              phase: finished
                  ? WifiOtaPhase.processing
                  : WifiOtaPhase.uploading,
              message: finished
                  ? 'Upload complete. SmartSpin2k is validating the image…'
                  : 'Uploading $firmwareFilename • ${_formatBytes(sent)} / ${_formatBytes(total)}',
              fraction: fraction,
              bytesSent: sent,
              totalBytes: total,
            ),
          );
        },
      );

      // Use a simple stream for all cases
      final multipartFile = createFirmwareMultipart(
        firmwareBytes,
        firmwareFilename,
      );
      request.files.add(multipartFile);

      print('WiFi OTA: Sending firmware...');
      final response = await httpClient
          .send(request)
          .timeout(const Duration(minutes: 5));
      final responseBody = await response.stream.bytesToString().timeout(
        const Duration(seconds: 30),
      );
      final result = resultForResponse(response.statusCode, responseBody);
      if (result.accepted) {
        onProgress(
          const WifiOtaProgress(
            phase: WifiOtaPhase.accepted,
            message: 'Update accepted. Waiting for SmartSpin2k to restart…',
            fraction: 1,
          ),
        );
        print('WiFi OTA: Upload accepted; device will reboot');
      } else {
        print(
          'WiFi OTA: Device rejected upload (${response.statusCode}): ${result.message}',
        );
      }
      return result;
    } on TimeoutException {
      const message = 'WiFi upload timed out before SmartSpin2k responded.';
      print('WiFi OTA: $message');
      return const WifiOtaResult(
        outcome: WifiOtaOutcome.failed,
        message: message,
      );
    } catch (error) {
      final message = 'WiFi upload failed: $error';
      print('WiFi OTA: $message');
      return WifiOtaResult(outcome: WifiOtaOutcome.failed, message: message);
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static WifiOtaResult resultForResponse(int statusCode, String body) {
    final message = body.trim();
    if (statusCode >= 200 && statusCode < 300) {
      return WifiOtaResult(
        outcome: WifiOtaOutcome.accepted,
        message: 'Update accepted. Waiting for SmartSpin2k to restart…',
        statusCode: statusCode,
      );
    }
    return WifiOtaResult(
      outcome: WifiOtaOutcome.rejected,
      message: message.isEmpty
          ? 'SmartSpin2k rejected the firmware image (HTTP $statusCode).'
          : message,
      statusCode: statusCode,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Creates the multipart field using the filename the firmware expects for
  /// its detected architecture (`firmware.bin` or `S3firmware.bin`).
  static http.MultipartFile createFirmwareMultipart(
    List<int> firmwareBytes,
    String firmwareFilename,
  ) {
    final filename = firmwareFilename.split(RegExp(r'[/\\]')).last;
    if (filename.isEmpty) {
      throw ArgumentError.value(
        firmwareFilename,
        'firmwareFilename',
        'Firmware filename must not be empty',
      );
    }
    return http.MultipartFile(
      'update',
      _firmwareChunks(firmwareBytes),
      firmwareBytes.length,
      filename: filename,
      contentType: MediaType('application', 'octet-stream'),
    );
  }

  static Stream<List<int>> _firmwareChunks(List<int> bytes) async* {
    const chunkSize = 16 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      yield bytes.sublist(offset, end);
      // Let UI frames run between chunks. Progress still represents bytes
      // consumed by the HTTP request; this adds no synthetic timed progress.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Builds OTA endpoints in priority order for diagnostics and tests. Runtime
  /// probing applies one shared timeout to the entire mDNS stage.
  static List<String> candidateBaseUrls({
    required String deviceName,
    String? deviceIp,
    String? mdnsIp,
  }) {
    final cleanDeviceName = deviceName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim();
    return <String>{
      if (deviceIp != null && deviceIp.isNotEmpty) 'http://$deviceIp',
      if (mdnsIp != null && mdnsIp.isNotEmpty) 'http://$mdnsIp',
      'http://$cleanDeviceName.local',
    }.toList();
  }

  static Future<String?> _locateWithMdns(
    http.Client client,
    String mdnsHost,
    Duration timeout,
  ) async {
    String? mdnsIp;
    if (Platform.isAndroid) {
      mdnsIp = await _resolveMdnsAddress(mdnsHost);
      if (mdnsIp != null) {
        print('WiFi OTA: mDNS resolved $mdnsHost to $mdnsIp');
      } else {
        print('WiFi OTA: mDNS lookup for $mdnsHost returned no address');
      }
    }

    final candidates = <String>{
      if (mdnsIp != null && mdnsIp.isNotEmpty) 'http://$mdnsIp',
      'http://$mdnsHost',
    };
    for (final candidate in candidates) {
      print('WiFi OTA: Attempting mDNS endpoint: $candidate');
      if (await _checkDeviceAvailability(client, candidate, timeout: timeout)) {
        return candidate;
      }
    }
    return null;
  }

  static Future<bool> _checkDeviceAvailability(
    http.Client client,
    String baseUrl, {
    required Duration timeout,
  }) async {
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/OTAIndex'))
          .timeout(timeout);
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
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(hostname),
          )
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

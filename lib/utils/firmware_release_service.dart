import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'firmware_architecture.dart';

class FirmwareRelease {
  const FirmwareRelease({
    required this.version,
    required this.downloadUrl,
    this.manifestUrl,
    this.manifestSignatureUrl,
    this.isMostRecent = false,
  });

  final String version;
  final String downloadUrl;
  final String? manifestUrl;
  final String? manifestSignatureUrl;
  final bool isMostRecent;

  String get displayName =>
      isMostRecent ? 'Most Recent Release ($version)' : version;
}

class FirmwareReleaseService {
  const FirmwareReleaseService();

  static final Uri releasesUri = Uri.parse(
    'https://api.github.com/repos/doudar/SmartSpin2k/releases',
  );

  /// Test seam: when set, [fetchAll] returns these releases instead of
  /// calling GitHub. Headless captures have no network. Never set in
  /// production code.
  @visibleForTesting
  static List<FirmwareRelease>? debugReleasesOverride;

  /// Whether a test has injected releases via [debugReleasesOverride].
  static bool get hasDebugReleasesOverride => debugReleasesOverride != null;

  Future<List<FirmwareRelease>> fetchAll() async {
    final override = debugReleasesOverride;
    if (override != null) return List.of(override);
    final response = await http
        .get(releasesUri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException(
        'Unable to check firmware releases (HTTP ${response.statusCode}).',
      );
    }
    return parseFirmwareReleases(response.body);
  }
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<FirmwareRelease> parseFirmwareReleases(String responseBody) {
  final decoded = json.decode(responseBody);
  if (decoded is! List) {
    throw const FormatException('GitHub release response was not a list.');
  }

  final releases = <FirmwareRelease>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic> ||
        item['draft'] == true ||
        item['prerelease'] == true) {
      continue;
    }

    final tag = item['tag_name'];
    final assets = item['assets'];
    if (tag is! String || assets is! List) continue;

    final expectedAsset = expectedReleaseAssetName(tag);
    final urls = <String, String>{};
    final duplicates = <String>{};
    for (final asset in assets.whereType<Map>()) {
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String ||
          url is! String ||
          Uri.tryParse(url)?.scheme != 'https')
        continue;
      if (urls.containsKey(name)) duplicates.add(name);
      urls[name] = url;
    }
    final requiredNames = [
      expectedAsset,
      'firmware-manifest.json',
      'firmware-manifest.sig',
    ];
    if (requiredNames.every(
      (name) => urls.containsKey(name) && !duplicates.contains(name),
    )) {
      releases.add(
        FirmwareRelease(
          version: tag,
          downloadUrl: urls[expectedAsset]!,
          manifestUrl: urls['firmware-manifest.json']!,
          manifestSignatureUrl: urls['firmware-manifest.sig']!,
          isMostRecent: releases.isEmpty,
        ),
      );
    }
  }
  return releases;
}

/// Compares the three-part release version while ignoring hardware and git
/// suffixes such as `-S3-51-g312ab07` reported by development builds.
bool isFirmwareVersionNewer(String available, String installed) {
  final availableParts = _releaseVersionParts(available);
  final installedParts = _releaseVersionParts(installed);
  if (availableParts.isEmpty || installedParts.isEmpty) return false;

  for (var index = 0; index < 3; index++) {
    final availablePart = index < availableParts.length
        ? availableParts[index]
        : 0;
    final installedPart = index < installedParts.length
        ? installedParts[index]
        : 0;
    if (availablePart != installedPart) {
      return availablePart > installedPart;
    }
  }
  return false;
}

bool firmwareUpdateVersionConfirmed(
  String original,
  String reported,
  String? target, {
  required bool receiptMissing,
}) {
  if (_releaseVersionParts(reported).length < 3) return false;
  if (target != null && !firmwareVersionsMatch(target, reported)) return false;
  if (target == null || receiptMissing) {
    return _releaseVersionParts(original).length == 3 &&
        !firmwareVersionsMatch(original, reported);
  }
  return true;
}

/// Matches the release portion even when the trainer appends build metadata.
bool firmwareVersionsMatch(String expected, String reported) {
  final expectedParts = _releaseVersionParts(expected);
  final reportedParts = _releaseVersionParts(reported);
  if (expectedParts.length < 3 || reportedParts.length < 3) return false;

  for (var index = 0; index < 3; index++) {
    if (expectedParts[index] != reportedParts[index]) return false;
  }
  return true;
}

List<int> _releaseVersionParts(String version) => RegExp(r'\d+')
    .allMatches(version)
    .take(3)
    .map((match) => int.parse(match.group(0)!))
    .toList();

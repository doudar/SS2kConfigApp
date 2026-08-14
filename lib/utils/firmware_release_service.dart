import 'dart:convert';

import 'package:http/http.dart' as http;

import 'firmware_architecture.dart';

class FirmwareRelease {
  const FirmwareRelease({
    required this.version,
    required this.downloadUrl,
    this.isMostRecent = false,
  });

  final String version;
  final String downloadUrl;
  final bool isMostRecent;

  String get displayName =>
      isMostRecent ? 'Most Recent Release ($version)' : version;
}

class FirmwareReleaseService {
  const FirmwareReleaseService();

  static final Uri releasesUri = Uri.parse(
    'https://api.github.com/repos/doudar/SmartSpin2k/releases',
  );

  Future<List<FirmwareRelease>> fetchAll() async {
    final response = await http.get(releasesUri);
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

    String? downloadUrl;
    final expectedAsset = expectedReleaseAssetName(tag);
    for (final asset in assets) {
      if (asset is Map<String, dynamic> && asset['name'] == expectedAsset) {
        final url = asset['browser_download_url'];
        if (url is String) downloadUrl = url;
        break;
      }
    }

    if (downloadUrl != null) {
      releases.add(
        FirmwareRelease(
          version: tag,
          downloadUrl: downloadUrl,
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

List<int> _releaseVersionParts(String version) => RegExp(r'\d+')
    .allMatches(version)
    .take(3)
    .map((match) => int.parse(match.group(0)!))
    .toList();

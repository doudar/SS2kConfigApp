import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const googlePlayAppUrl =
    'https://play.google.com/store/apps/details?id=com.smartspin2k.app&hl=en_US';
const appleAppStoreUrl =
    'https://apps.apple.com/us/app/smartspin2k-companion-app/id6477836948';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.releasePageUrl,
    this.androidApkUrl,
  });

  final String version;
  final String releasePageUrl;
  final String? androidApkUrl;
}

class AppReleaseService {
  const AppReleaseService();

  static final Uri releasesUri = Uri.parse(
    'https://api.github.com/repos/doudar/SS2kConfigApp/releases',
  );

  Future<AppRelease?> fetchLatest() async {
    final response = await http.get(releasesUri);
    if (response.statusCode != 200) {
      throw AppReleaseException(
        'Unable to check app releases (HTTP ${response.statusCode}).',
      );
    }
    return parseLatestAppRelease(response.body);
  }
}

class AppReleaseException implements Exception {
  const AppReleaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

AppRelease? parseLatestAppRelease(String responseBody) {
  final decoded = json.decode(responseBody);
  if (decoded is! List) {
    throw const FormatException('GitHub app release response was not a list.');
  }

  for (final item in decoded) {
    if (item is! Map<String, dynamic> ||
        item['draft'] == true ||
        item['prerelease'] == true) {
      continue;
    }

    final tag = item['tag_name'];
    final releasePageUrl = item['html_url'];
    final assets = item['assets'];
    if (tag is! String || releasePageUrl is! String || assets is! List) {
      continue;
    }

    String? androidApkUrl;
    final expectedApkName = 'ss2kconfigapp-$tag.apk'.toLowerCase();
    for (final asset in assets) {
      if (asset is Map<String, dynamic> &&
          asset['name']?.toString().toLowerCase() == expectedApkName) {
        final url = asset['browser_download_url'];
        if (url is String) androidApkUrl = url;
        break;
      }
    }

    return AppRelease(
      version: tag,
      releasePageUrl: releasePageUrl,
      androidApkUrl: androidApkUrl,
    );
  }
  return null;
}

bool isAppVersionNewer(String available, String installed) {
  final availableVersion = _parseAppVersion(available);
  final installedVersion = _parseAppVersion(installed);
  if (availableVersion == null || installedVersion == null) return false;

  for (var index = 0; index < availableVersion.length; index++) {
    if (availableVersion[index] != installedVersion[index]) {
      return availableVersion[index] > installedVersion[index];
    }
  }
  return false;
}

/// GitHub may append `-1`, `-2`, etc. when rebuilding an existing pubspec
/// version. Those tags contain the same application version and build number,
/// so only the `major.minor.patch+build` portion participates in comparison.
List<int>? _parseAppVersion(String version) {
  final match = RegExp(r'(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?').firstMatch(version);
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.tryParse(match.group(4) ?? '') ?? 0,
  ];
}

Uri appUpdateDestination({
  required TargetPlatform platform,
  required String? installerStore,
  required AppRelease release,
}) {
  if (platform == TargetPlatform.android) {
    if (installerStore?.toLowerCase() == 'com.android.vending') {
      return Uri.parse(googlePlayAppUrl);
    }
    return Uri.parse(release.androidApkUrl ?? release.releasePageUrl);
  }
  if (platform == TargetPlatform.iOS) {
    return Uri.parse(appleAppStoreUrl);
  }
  return Uri.parse(release.releasePageUrl);
}

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/app_release_service.dart';

void main() {
  const release = AppRelease(
    version: '1.3.3+67',
    releasePageUrl: 'https://github.com/doudar/SS2kConfigApp/releases/67',
    androidApkUrl: 'https://github.com/doudar/SS2kConfigApp/app-67.apk',
  );

  group('app version comparison', () {
    test('detects newer semantic and build versions', () {
      expect(isAppVersionNewer('1.4.0+1', '1.3.9+99'), isTrue);
      expect(isAppVersionNewer('1.3.2+67', '1.3.2+66'), isTrue);
    });

    test('does not treat a release retry suffix as a new app build', () {
      expect(isAppVersionNewer('1.3.2+66-1', '1.3.2+66'), isFalse);
    });

    test('rejects equal, older, and malformed versions', () {
      expect(isAppVersionNewer('1.3.2+66', '1.3.2+66'), isFalse);
      expect(isAppVersionNewer('1.3.1+99', '1.3.2+1'), isFalse);
      expect(isAppVersionNewer('latest', '1.3.2+66'), isFalse);
    });
  });

  group('app release parsing', () {
    test('skips prereleases and locates the exact Android APK', () {
      final parsed = parseLatestAppRelease('''
        [
          {
            "tag_name": "1.4.0+68-beta",
            "html_url": "https://example.com/beta",
            "draft": false,
            "prerelease": true,
            "assets": []
          },
          {
            "tag_name": "1.3.3+67",
            "html_url": "https://example.com/release",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "ss2kconfigapp-1.3.3+67.apk",
                "browser_download_url": "https://example.com/app.apk"
              }
            ]
          }
        ]
      ''');

      expect(parsed?.version, '1.3.3+67');
      expect(parsed?.androidApkUrl, 'https://example.com/app.apk');
    });
  });

  group('update destination', () {
    test('Google Play installs return to Google Play', () {
      final destination = appUpdateDestination(
        platform: TargetPlatform.android,
        installerStore: 'com.android.vending',
        release: release,
      );
      expect(destination.toString(), googlePlayAppUrl);
    });

    test('sideloaded Android installs receive the release APK', () {
      final destination = appUpdateDestination(
        platform: TargetPlatform.android,
        installerStore: null,
        release: release,
      );
      expect(destination.toString(), release.androidApkUrl);
    });

    test('iOS installs return to the App Store', () {
      final destination = appUpdateDestination(
        platform: TargetPlatform.iOS,
        installerStore: null,
        release: release,
      );
      expect(destination.toString(), appleAppStoreUrl);
    });

    test('desktop builds use the GitHub release page', () {
      final destination = appUpdateDestination(
        platform: TargetPlatform.windows,
        installerStore: null,
        release: release,
      );
      expect(destination.toString(), release.releasePageUrl);
    });
  });
}

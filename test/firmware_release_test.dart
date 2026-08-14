/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/firmware_release_service.dart';

void main() {
  group('FirmwareRelease', () {
    test('displayName returns correct format for most recent release', () {
      final release = FirmwareRelease(
        version: '25.9.22',
        downloadUrl: 'https://example.com/firmware.zip',
        isMostRecent: true,
      );

      expect(release.displayName, equals('Most Recent Release (25.9.22)'));
    });

    test('displayName returns version for regular release', () {
      final release = FirmwareRelease(
        version: '25.5.31',
        downloadUrl: 'https://example.com/firmware.zip',
      );

      expect(release.displayName, equals('25.5.31'));
    });

    test('isMostRecent defaults to false', () {
      final release = FirmwareRelease(
        version: '25.9.22',
        downloadUrl: 'https://example.com/firmware.zip',
      );

      expect(release.isMostRecent, isFalse);
    });

    test('can create list of releases with proper ordering', () {
      final releases = [
        FirmwareRelease(
          version: '25.9.22',
          downloadUrl: 'https://example.com/25.9.22.zip',
          isMostRecent: true,
        ),
        FirmwareRelease(
          version: '25.5.31',
          downloadUrl: 'https://example.com/25.5.31.zip',
        ),
        FirmwareRelease(
          version: '24.8.30',
          downloadUrl: 'https://example.com/24.8.30.zip',
        ),
      ];

      expect(releases.length, equals(3));
      expect(releases[0].isMostRecent, isTrue);
      expect(releases[1].displayName, equals('25.5.31'));
      expect(releases[2].displayName, equals('24.8.30'));
    });
  });

  group('version comparison', () {
    test('detects a newer release', () {
      expect(isFirmwareVersionNewer('26.8.1', '26.7.15'), isTrue);
    });

    test('ignores an installed development-build suffix', () {
      expect(
        isFirmwareVersionNewer('26.7.15', '26.7.15-S3-51-g312ab07'),
        isFalse,
      );
    });

    test('does not offer an older release', () {
      expect(isFirmwareVersionNewer('25.9.22', '26.1.1'), isFalse);
    });
  });

  group('GitHub release parsing', () {
    test('uses the newest stable release with a firmware package', () {
      final releases = parseFirmwareReleases('''
        [
          {
            "tag_name": "26.9.1-beta",
            "draft": false,
            "prerelease": true,
            "assets": []
          },
          {
            "tag_name": "26.8.2",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "SmartSpin2kFirmware-26.8.2.bin.zip",
                "browser_download_url": "https://example.com/26.8.2.zip"
              }
            ]
          },
          {
            "tag_name": "26.8.1",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "SmartSpin2kFirmware-26.8.1.bin.zip",
                "browser_download_url": "https://example.com/26.8.1.zip"
              }
            ]
          }
        ]
      ''');

      expect(releases.map((release) => release.version), ['26.8.2', '26.8.1']);
      expect(releases.first.isMostRecent, isTrue);
      expect(releases.last.isMostRecent, isFalse);
    });
  });
}

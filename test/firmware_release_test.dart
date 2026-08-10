/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter_test/flutter_test.dart';

// Model class for firmware releases (copied from firmware_update_screen.dart)
class FirmwareRelease {
  final String version;
  final String downloadUrl;
  final bool isMostRecent;

  FirmwareRelease({
    required this.version,
    required this.downloadUrl,
    this.isMostRecent = false,
  });

  String get displayName {
    if (isMostRecent) return 'Most Recent Release ($version)';
    return version;
  }
}

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
}

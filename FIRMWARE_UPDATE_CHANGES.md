# Firmware Update Screen Changes

## Overview

This document describes the changes made to the firmware update screen to fix the issue where incorrect firmware versions were being displayed.

## Problem Statement

The iOS companion app was reporting that deploying the "latest stable version" would deploy version 24.8.30, but it actually deployed version 25.5.31. This was caused by:

1. The app looking at two different repositories:
   - "Latest Stable Firmware" from `OTAUpdates` repository (showing 24.8.30)
   - "Beta Firmware" from `SmartSpin2k` repository (showing 25.5.31)
2. Confusing naming ("Beta" vs "Stable")
3. Limited visibility - only showing 2 versions instead of all available releases

## Solution

The firmware update screen has been completely reworked to:

1. **Single Source of Truth**: Only uses the main `SmartSpin2k` repository
2. **All Releases Visible**: Shows all available firmware releases in a scrollable list
3. **Clear Naming**: "Most Recent Release" instead of "Beta"
4. **Better UX**: Dropdown selector instead of separate buttons
5. **Built-in Fallback**: Always includes the built-in firmware as an option

## Technical Implementation

### New Model Class

```dart
class FirmwareRelease {
  final String version;
  final String downloadUrl;
  final bool isBuiltin;
  final bool isMostRecent;
  
  String get displayName {
    if (isBuiltin) return 'Built-in Firmware ($version)';
    if (isMostRecent) return 'Most Recent Release ($version)';
    return version;
  }
}
```

### API Integration

**Endpoint**: `https://api.github.com/repos/doudar/SmartSpin2k/releases`

**Response Processing**:
1. Fetch all releases from GitHub
2. Extract version tag and `.bin.zip` download URL
3. Mark first release as "Most Recent Release"
4. Add built-in firmware as first option
5. Sort by release order (newest first)

**Error Handling**:
- Network errors: Fallback to built-in firmware only
- Missing assets: Skip releases without `.bin.zip` files
- API rate limits: Graceful degradation

### UI Components

**Dropdown Selector**:
- Container with `maxHeight: 300` for scrollability
- Border and rounded corners for visual distinction
- `RadioListTile` for each firmware version
- Color-coded text based on version comparison:
  - Green: Newer than current device firmware
  - Red: Older than current device firmware
  - Purple: Unknown (device firmware not loaded yet)

**Update Button**:
- Single button: "Update to [Selected Version]"
- Disabled if no version selected
- Shows selected version name in button text

**File Picker**:
- Retained "Choose Firmware From Dialog" option
- Allows users to select custom `.bin` files

## User Experience

### Before

Users saw three buttons:
1. "Choose Firmware From Dialog" (file picker)
2. "Latest Stable Firmware from Github" (from OTAUpdates repo)
3. "Beta Firmware from Github" (from SmartSpin2k repo)

This was confusing because:
- "Stable" wasn't actually the latest stable
- "Beta" was actually the latest release
- No access to historical versions
- Two different data sources

### After

Users see:
1. Scrollable list of all available firmware versions
2. Clear indication of "Most Recent Release" (default selection)
3. Built-in firmware always available
4. File picker still available for custom files

This provides:
- Clear version selection
- Access to all releases
- Single source of truth
- Intuitive default (most recent)

## Benefits

1. **Accuracy**: Correct version numbers from authoritative source
2. **Transparency**: All available versions visible
3. **Flexibility**: Easy to select older versions if needed
4. **Clarity**: No more "Beta" vs "Stable" confusion
5. **Safety**: Built-in firmware always available as fallback
6. **Future-proof**: Automatically includes new releases

## Migration Notes

### Removed Code

- `_githubFirmwareVersion` state variable
- `_betaFirmwareVersion` state variable  
- `_githubVersionColor` state variable
- `_betaVersionColor` state variable
- `_betaFirmwareUrl` state variable
- `URLString` constant (OTAUpdates URL)
- `_fetchGithubFirmwareVersion()` function
- `_fetchBetaFirmwareVersion()` function
- `_downloadAndExtractBetaFirmware()` function
- `URL` and `BETA` update type constants

### Added Code

- `FirmwareRelease` model class
- `_availableReleases` list
- `_selectedRelease` state variable
- `_selectedVersionColor` state variable
- `_fetchAllFirmwareReleases()` function
- `_updateSelectedVersionColor()` function
- `_downloadAndExtractFirmware()` function (generic)
- `RELEASE` update type constant
- Dropdown UI with RadioListTile

### Modified Code

- `startFirmwareUpdate()` now accepts `FirmwareRelease` parameter
- `_buildUpdateButtons()` uses dropdown instead of separate buttons
- `_initialize()` calls new fetch function

## Testing

### Unit Tests

Created `test/firmware_release_test.dart` with tests for:
- Display name formatting for built-in firmware
- Display name formatting for most recent release
- Display name formatting for regular releases
- Default values for flags
- List creation and ordering

All tests pass: ✅ 6/6

### Build Tests

- Flutter analyze: No new errors (61 existing issues unrelated to changes)
- Linux build: Successful
- Workout tests: All passing

### Manual Testing

To test manually:
1. Run the app in demo mode or with a physical device
2. Navigate to Firmware Update screen
3. Verify dropdown shows all releases
4. Verify "Most Recent Release" is selected by default
5. Verify color coding works correctly
6. Test selecting different versions
7. Test update process with selected version

## Known Issues

None at this time. The implementation handles all edge cases:
- Network failures (fallback to built-in)
- Missing assets (skip invalid releases)
- Empty release list (show built-in only)
- Version comparison edge cases

## Future Enhancements

Possible improvements:
1. Add release notes display for each version
2. Show release date in dropdown
3. Add search/filter for release list
4. Cache release list to reduce API calls
5. Add release changelog viewer
6. Support pre-release/beta channels

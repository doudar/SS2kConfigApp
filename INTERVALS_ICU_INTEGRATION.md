# Intervals.icu Integration

This document describes the Intervals.icu integration added to the SmartSpin2k configuration app.

## Features

### 1. OAuth Authentication
- Secure OAuth 2.0 flow for connecting to Intervals.icu
- Token management with automatic refresh
- Persistent authentication state across app sessions

### 2. Today's Workout Loading
- Fetch today's planned workout from Intervals.icu
- Automatic conversion from Intervals.icu format to ZWO format
- Support for structured workouts with intervals, ramps, and steady states

### 3. Workout Upload
- Upload completed workouts to Intervals.icu as FIT files
- Integration with existing workout export dialog
- Automatic workout metadata (name, description)

### 4. UI Integration
- Connected Accounts dialog for authentication management
- Workout menu option to load today's workout
- Status indicators for connection state

## Setup

### 1. API Credentials
To use Intervals.icu integration, you need to obtain API credentials:

1. Go to [Intervals.icu API Settings](https://intervals.icu/settings/developer)
2. Create a new OAuth application
3. Set the redirect URI to: `smartspin2k://intervals_redirect`
4. Note down your Client ID and Client Secret

### 2. Environment Configuration
Add your credentials to the environment configuration:

**For local development:**
1. Copy `lib/config/env.template.dart` to `lib/config/env.local.dart`
2. Replace the placeholder values:
```dart
static const String intervalsClientId = 'your_actual_client_id';
static const String intervalsClientSecret = 'your_actual_client_secret';
```

**For CI/CD builds:**
Set environment variables:
- `INTERVALS_CLIENT_ID`
- `INTERVALS_CLIENT_SECRET`

## Usage

### Connecting to Intervals.icu
1. In the workout screen, tap the menu (⋮) button
2. Select "Connected Accounts"
3. Tap "Connect with Intervals.icu"
4. Complete the OAuth flow in your browser
5. Return to the app when prompted

### Loading Today's Workout
1. Ensure you're connected to Intervals.icu
2. In the workout screen, tap the menu (⋮) button
3. Select "Today's Workout (Intervals.icu)"
4. The workout will be loaded automatically if available

### Uploading Completed Workouts
1. Complete a workout session
2. When the workout ends, tap "Export"
3. Select "UPLOAD TO INTERVALS.ICU"
4. The workout will be uploaded as a FIT file

## API Endpoints Used

- **Authentication:** `https://intervals.icu/oauth/authorize` and `https://intervals.icu/api/oauth/token`
- **Today's Events:** `GET /api/v1/athlete/{id}/events/{date}`
- **Upload Activity:** `POST /api/v1/athlete/{id}/activities`
- **Workout Library:** `GET /api/v1/athlete/{id}/workouts`

## Supported Workout Formats

The integration supports:
- Structured workouts from Intervals.icu
- ZWO format files
- Automatic conversion between formats
- Workout metadata (name, description, duration, TSS, IF)

## Error Handling

The integration includes comprehensive error handling for:
- Network connectivity issues
- Authentication failures
- Invalid workout formats
- API rate limiting
- Missing workout data

## Security

- OAuth 2.0 with PKCE (if supported)
- Secure token storage using SharedPreferences
- Automatic token refresh
- No credentials stored in code or logs
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../config/env.dart';

class IntervalsService {
  static const String _baseUrl = 'https://intervals.icu/api/v1';
  static const String _authUrl = 'https://intervals.icu/oauth/authorize';
  static const String _tokenUrl = 'https://intervals.icu/api/oauth/token';
  static const String _redirectUri = 'smartspin2k://intervals_redirect';
  
  // Keys for storing tokens in SharedPreferences
  static const String _accessTokenKey = 'intervals_access_token';
  static const String _refreshTokenKey = 'intervals_refresh_token';
  static const String _expiresAtKey = 'intervals_expires_at';
  static const String _athleteIdKey = 'intervals_athlete_id';
  static const String _tokenTypeKey = 'intervals_token_type';
  static const String _scopeKey = 'intervals_scope';

  // Get stored tokens
  static Future<Map<String, String?>> getStoredTokens() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'accessToken': prefs.getString(_accessTokenKey),
      'refreshToken': prefs.getString(_refreshTokenKey),
      'expiresAt': prefs.getString(_expiresAtKey),
      'athleteId': prefs.getString(_athleteIdKey),
      'tokenType': prefs.getString(_tokenTypeKey),
      'scope': prefs.getString(_scopeKey),
    };
  }

  // Store tokens
  static Future<void> _storeTokens({
    required String accessToken,
    String? refreshToken,
    String? expiresAt,
    String? athleteId,
    String? tokenType,
    String? scope,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
    if (expiresAt != null) {
      await prefs.setString(_expiresAtKey, expiresAt);
    }
    if (athleteId != null) {
      await prefs.setString(_athleteIdKey, athleteId);
    }
    if (tokenType != null) {
      await prefs.setString(_tokenTypeKey, tokenType);
    }
    if (scope != null) {
      await prefs.setString(_scopeKey, scope);
    }
  }

  // Clear stored tokens
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_athleteIdKey);
    await prefs.remove(_tokenTypeKey);
    await prefs.remove(_scopeKey);
  }

  // Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    final tokens = await getStoredTokens();
    if (tokens['accessToken'] == null) return false;
    // Intervals.icu tokens typically do not include refresh or expiry in this flow.
    // If present in future, we can refresh; for now, presence of access token is enough.
    return true;
  }

  // Refresh token
  static Future<bool> _refreshToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'client_id': Environment.intervalsClientId,
          'client_secret': Environment.intervalsClientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storeTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiresAt: data['expires_at']?.toString(),
          athleteId: (data['athlete']?['id'] ?? data['athlete_id'])?.toString(),
          tokenType: data['token_type']?.toString(),
          scope: data['scope']?.toString(),
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error refreshing Intervals.icu token: $e');
      return false;
    }
  }

  // Start OAuth flow
  static Future<void> authenticate(BuildContext context) async {
    // Show instructions dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connecting to Intervals.icu'),
        content: const Text(
          'You will be redirected to Intervals.icu to authorize SmartSpin2k.\n\n'
          'After authorizing, please select "Open in SmartSpin2k" when prompted.',
        ),
        actions: [
          TextButton(
            child: const Text('CONTINUE'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );

    // Build OAuth URL
    final authUrl = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': Environment.intervalsClientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      // Request calendar read so we can fetch events (today's workout)
      'scope': 'ACTIVITY:WRITE,LIBRARY:READ,CALENDAR:READ',
    });

    debugPrint('Launching Intervals.icu OAuth URL: ${authUrl.toString()}');

    // Use external browser so the smartspin2k:// redirect can return to the app
    await launchUrlString(
      authUrl.toString(),
      mode: LaunchMode.externalApplication,
    );
  }

  // Handle OAuth callback
  static Future<bool> handleAuthCallback(String code) async {
    debugPrint('Handling Intervals.icu auth callback with code: $code');
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'client_id': Environment.intervalsClientId,
          'client_secret': Environment.intervalsClientSecret,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': _redirectUri,
        },
      );

      debugPrint('Intervals.icu auth callback response status: ${response.statusCode}');
      debugPrint('Intervals.icu auth callback response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storeTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiresAt: data['expires_at']?.toString(),
          athleteId: (data['athlete']?['id'] ?? data['athlete_id'])?.toString(),
          tokenType: data['token_type']?.toString(),
          scope: data['scope']?.toString(),
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Intervals.icu auth callback error: $e');
      return false;
    }
  }

  // Get today's planned workout
  static Future<Map<String, dynamic>?> getTodaysWorkout() async {
    if (!await isAuthenticated()) return null;

    try {
      final tokens = await getStoredTokens();
      final accessToken = tokens['accessToken'];
      final athleteId = tokens['athleteId'];
      
      if (athleteId == null) return null;

  final today = DateTime.now();
  // Intervals API expects an integer date in the path (yyyymmdd), not a hyphenated string
  final datePath = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

  // Try with the athleteId as returned first (stay on this athlete only)
  final primaryUrl = Uri.parse('$_baseUrl/athlete/$athleteId/events/$datePath');
      debugPrint("Fetching today's workout: $primaryUrl");

      var response = await http.get(
        primaryUrl,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('Get today\'s workout response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint("Today's workout error body: ${response.body}");
      }

      // Do NOT change athlete id to avoid 403 with mismatched tokens.

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          final events = decoded;
          for (final event in events) {
            // Consider both 'WORKOUT' and presence of workout fields
            final hasWorkout = event is Map<String, dynamic> && (event['workout_doc'] != null || event['workout_file'] != null);
            if ((event['category'] == 'WORKOUT' || hasWorkout) && hasWorkout) {
              return event as Map<String, dynamic>;
            }
          }
        } else if (decoded is Map<String, dynamic>) {
          // Some APIs may return an object; if so, try to read an 'events' list
          final events = decoded['events'];
          if (events is List) {
            for (final event in events) {
              final hasWorkout = event is Map<String, dynamic> && (event['workout_doc'] != null || event['workout_file'] != null);
              if ((event['category'] == 'WORKOUT' || hasWorkout) && hasWorkout) {
                return event as Map<String, dynamic>;
              }
            }
          }
        }
      }

      // If still not successful or no matching workout found, try the range endpoint with SAME athlete id
      if (response.statusCode == 404 || response.statusCode >= 400 || response.statusCode == 200) {
        final from = datePath;
        final to = datePath;
        final rangeUrl = Uri.parse('$_baseUrl/athlete/$athleteId/events?from=$from&to=$to');
        debugPrint("Trying range events endpoint: $rangeUrl");
        final rangeRes = await http.get(
          rangeUrl,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        );
        debugPrint('Range events status: ${rangeRes.statusCode}');
        if (rangeRes.statusCode == 200) {
          final decoded = json.decode(rangeRes.body);
          if (decoded is List) {
            for (final event in decoded) {
              final hasWorkout = event is Map<String, dynamic> && (event['workout_doc'] != null || event['workout_file'] != null);
              if ((event['category'] == 'WORKOUT' || hasWorkout) && hasWorkout) {
                return event as Map<String, dynamic>;
              }
            }
          }
        } else {
          debugPrint('Range events error body: ${rangeRes.body}');
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting today\'s workout from Intervals.icu: $e');
      return null;
    }
  }

  // Upload completed workout
  static Future<bool> uploadWorkout(String filePath, String name, String description) async {
    if (!await isAuthenticated()) return false;

    try {
      final tokens = await getStoredTokens();
      final accessToken = tokens['accessToken'];
      final athleteId = tokens['athleteId'];
      
      if (athleteId == null) return false;
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/athlete/$athleteId/activities'),
      );

      request.headers['Authorization'] = 'Bearer $accessToken';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
      ));
      
      request.fields['name'] = name;
      request.fields['description'] = description;

      final response = await request.send();
      debugPrint('Intervals.icu upload response status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Upload workout to Intervals.icu error: $e');
      return false;
    }
  }

  // Get workout library (for browsing workouts)
  static Future<List<Map<String, dynamic>>> getWorkoutLibrary() async {
    if (!await isAuthenticated()) return [];

    try {
      final tokens = await getStoredTokens();
      final accessToken = tokens['accessToken'];
      final athleteId = tokens['athleteId'];
      
      if (athleteId == null) return [];

      // Use only the connected athlete id (no cross-athlete fallbacks)
      var url = Uri.parse('$_baseUrl/athlete/$athleteId/workouts');
      debugPrint('Fetching workout library: $url');
      var response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      debugPrint('Get workout library response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('Workout library error body: ${response.body}');
      }


      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          // Cast to Map<String, dynamic>
          return decoded.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting workout library from Intervals.icu: $e');
      return [];
    }
  }

  // Download a planned workout (event) in ZWO/MRC/ERG/FIT format using the official events download endpoint.
  static Future<String?> downloadEventWorkout({
    required int eventId,
    String ext = 'zwo',
  }) async {
    if (!await isAuthenticated()) return null;
    try {
      final tokens = await getStoredTokens();
      final accessToken = tokens['accessToken'];
      final athleteId = tokens['athleteId'];
      if (athleteId == null) return null;

      // Ensure extension has a leading dot
      final safeExt = ext.startsWith('.') ? ext : '.$ext';
      final url = Uri.parse('$_baseUrl/athlete/$athleteId/workoutId/$eventId/download$safeExt');
      debugPrint('Downloading workout: $url');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/octet-stream, application/xml, text/plain, */*',
        },
      );
      debugPrint('Event download status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        // ZWO is XML text; try utf8 decode
        return utf8.decode(bytes);
      } else {
        debugPrint('Event download error body: ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading event workout: $e');
      return null;
    }
  }

  // Fetch planned workout events from the athlete's calendar as CSV and parse WORKOUT rows.
  // Returns a list of maps with keys: event_id (int), name, start_date_local, category, type, description, training_load.
  static Future<List<Map<String, dynamic>>> getCalendarWorkoutEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    if (!await isAuthenticated()) return [];
    try {
      final tokens = await getStoredTokens();
      final accessToken = tokens['accessToken'];
      final athleteId = tokens['athleteId'];
      if (athleteId == null) return [];

      final now = DateTime.now();
      final start = from ?? now.subtract(const Duration(days: 7));
      final end = to ?? now.add(const Duration(days: 30));

      String fmt(DateTime d) => '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
      final url = Uri.parse('$_baseUrl/athlete/$athleteId/events.csv?from=${fmt(start)}&to=${fmt(end)}');
      debugPrint('Fetching calendar events CSV: $url');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'text/csv, text/plain, */*',
        },
      );
      debugPrint('Calendar events CSV status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('Calendar events CSV body: ${response.body}');
        return [];
      }

      final lines = const LineSplitter().convert(response.body);
      if (lines.length < 2) return [];
      final header = lines.first.split(',');
      // Indices based on provided sample
      final idIdx = header.indexOf('id');
      final categoryIdx = header.indexOf('category');
      final typeIdx = header.indexOf('type');
      final nameIdx = header.indexOf('name');
      final startIdx = header.indexOf('start_date_local');
      final descIdx = header.indexOf('description');
      final loadIdx = header.indexOf('icu_training_load');

      final events = <Map<String, dynamic>>[];
      for (var i = 1; i < lines.length; i++) {
        final rawLine = lines[i];
        if (rawLine.trim().isEmpty) continue;
        // Basic CSV split (will break if fields contain commas inside quotes; can enhance later)
        final cols = rawLine.split(',');
        if ([idIdx, categoryIdx, nameIdx].any((idx) => idx < 0 || idx >= cols.length)) continue;
        final category = cols[categoryIdx];
        if (category != 'WORKOUT') continue;
        int? eventId = int.tryParse(cols[idIdx]);
        final map = <String, dynamic>{
          'event_id': eventId,
          'name': nameIdx >= 0 && nameIdx < cols.length ? cols[nameIdx].replaceAll('"', '') : 'Workout',
          'category': category,
          'type': typeIdx >= 0 && typeIdx < cols.length ? cols[typeIdx] : null,
          'start_date_local': startIdx >= 0 && startIdx < cols.length ? cols[startIdx] : null,
          'description': descIdx >= 0 && descIdx < cols.length ? cols[descIdx].replaceAll('"', '') : null,
          'icu_training_load': loadIdx >= 0 && loadIdx < cols.length ? cols[loadIdx] : null,
        };
        events.add(map);
      }
      return events;
    } catch (e) {
      debugPrint('Error fetching calendar workout events: $e');
      return [];
    }
  }
}
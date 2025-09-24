import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/env.dart';

class IntervalsService {
  static const String _baseUrl = 'https://intervals.icu/api/v1';
  static const String _authUrl = 'https://intervals.icu/oauth/authorize';
  static const String _tokenUrl = 'https://intervals.icu/oauth/token';
  static const String _redirectUri = 'smartspin2k://intervals_redirect';
  
  // Keys for storing tokens in SharedPreferences
  static const String _accessTokenKey = 'intervals_access_token';
  static const String _refreshTokenKey = 'intervals_refresh_token';
  static const String _expiresAtKey = 'intervals_expires_at';
  static const String _athleteIdKey = 'intervals_athlete_id';

  // Get stored tokens
  static Future<Map<String, String?>> getStoredTokens() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'accessToken': prefs.getString(_accessTokenKey),
      'refreshToken': prefs.getString(_refreshTokenKey),
      'expiresAt': prefs.getString(_expiresAtKey),
      'athleteId': prefs.getString(_athleteIdKey),
    };
  }

  // Store tokens
  static Future<void> _storeTokens(String accessToken, String refreshToken, String expiresAt, String athleteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_expiresAtKey, expiresAt);
    await prefs.setString(_athleteIdKey, athleteId);
  }

  // Clear stored tokens
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_athleteIdKey);
  }

  // Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    final tokens = await getStoredTokens();
    if (tokens['accessToken'] == null) return false;
    
    // Check if token is expired
    if (tokens['expiresAt'] != null) {
      final expiresAt = int.parse(tokens['expiresAt']!);
      if (DateTime.now().millisecondsSinceEpoch / 1000 >= expiresAt) {
        // Token is expired, try to refresh
        return await _refreshToken(tokens['refreshToken']!);
      }
    }
    
    return true;
  }

  // Refresh token
  static Future<bool> _refreshToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
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
          data['access_token'],
          data['refresh_token'],
          data['expires_at'].toString(),
          data['athlete_id'].toString(),
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
      'scope': 'read write',
    });

    debugPrint('Launching Intervals.icu OAuth URL: ${authUrl.toString()}');

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
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
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
          data['access_token'],
          data['refresh_token'],
          data['expires_at'].toString(),
          data['athlete_id'].toString(),
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
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final response = await http.get(
        Uri.parse('$_baseUrl/athlete/$athleteId/events/$dateStr'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('Get today\'s workout response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final events = json.decode(response.body) as List;
        
        // Find the first workout event for today
        for (final event in events) {
          if (event['category'] == 'WORKOUT' && event['workout_doc'] != null) {
            return event;
          }
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
      
      final response = await http.get(
        Uri.parse('$_baseUrl/athlete/$athleteId/workouts'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('Get workout library response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final workouts = json.decode(response.body) as List;
        return workouts.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting workout library from Intervals.icu: $e');
      return [];
    }
  }

  // Debug method to check authentication status and basic info
  static Future<Map<String, dynamic>> getDebugInfo() async {
    final tokens = await getStoredTokens();
    final isAuth = await isAuthenticated();
    
    return {
      'isAuthenticated': isAuth,
      'hasAccessToken': tokens['accessToken'] != null,
      'hasRefreshToken': tokens['refreshToken'] != null,
      'hasAthleteId': tokens['athleteId'] != null,
      'expiresAt': tokens['expiresAt'],
    };
  }
}
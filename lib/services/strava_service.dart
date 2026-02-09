import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpServer, InternetAddress, ContentType, HttpRequest;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/env.dart';

class StravaService {
  static const String _baseUrl = 'https://www.strava.com/api/v3';
  static const String _authUrl = 'https://www.strava.com/oauth/authorize';
  static const String _mobileAuthUrl = 'https://www.strava.com/oauth/mobile/authorize';
  static const String _tokenUrl = 'https://www.strava.com/oauth/token';
  static const String _redirectUri = 'smartspin2k://redirect';
  
  // Keys for storing tokens in SharedPreferences
  static const String _accessTokenKey = 'strava_access_token';
  static const String _refreshTokenKey = 'strava_refresh_token';
  static const String _expiresAtKey = 'strava_expires_at';

  // Get stored tokens
  static Future<Map<String, String?>> getStoredTokens() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'accessToken': prefs.getString(_accessTokenKey),
      'refreshToken': prefs.getString(_refreshTokenKey),
      'expiresAt': prefs.getString(_expiresAtKey),
    };
  }

  // Store tokens
  static Future<void> _storeTokens(String accessToken, String refreshToken, String expiresAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_expiresAtKey, expiresAt);
  }

  // Clear stored tokens
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiresAtKey);
  }

  // Check if user is authenticated (refresh if needed)
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
        body: {
          'client_id': Environment.stravaClientId,
          'client_secret': Environment.stravaClientSecret,
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
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      return false;
    }
  }

  // Start OAuth flow
  static Future<void> authenticate(BuildContext context) async {
    // Show instructions dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connecting to Strava'),
        content: const Text(
          'You will be redirected to Strava to authorize SmartSpin2k.\n\n'
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
    // Helper to show a snack bar safely
    void showSnack(String msg) {
      final scaffold = ScaffoldMessenger.maybeOf(context);
      scaffold?.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    }

    Future<bool> _tryLaunch(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
      debugPrint('[StravaAuth] Attempting launch: $uri (mode=$mode)');
      try {
        final can = await canLaunchUrl(uri);
        if (!can) {
          debugPrint('[StravaAuth] canLaunchUrl returned false for: $uri');
          return false;
        }
        final launched = await launchUrl(uri, mode: mode);
        debugPrint('[StravaAuth] launchUrl result for $uri: $launched');
        return launched;
      } catch (e) {
        debugPrint('[StravaAuth] Exception launching $uri: $e');
        return false;
      }
    }

    // Desktop platforms cannot handle the custom scheme callback; use a local loopback redirect
    if (!Platform.isAndroid && !Platform.isIOS) {
      const int port = 8723;
      final redirectUri = 'http://localhost:$port/redirect';
      final params = {
        'client_id': Environment.stravaClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'activity:write,read',
      };

      final webStandardUrl = Uri.parse(_authUrl).replace(queryParameters: params);

      HttpServer? server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: false);
      } catch (e) {
        debugPrint('[StravaAuth] Failed to bind local redirect server: $e');
        showSnack('Unable to start local redirect listener for Strava auth');
        return;
      }

      await _tryLaunch(webStandardUrl, mode: LaunchMode.externalApplication);

      HttpRequest request;
      try {
        request = await server.first.timeout(const Duration(minutes: 2));
      } catch (e) {
        debugPrint('[StravaAuth] No callback received: $e');
        await server.close(force: true);
        showSnack('No response received from Strava (timeout)');
        return;
      }

      final code = request.uri.queryParameters['code'];

      // Friendly response in the browser
      request.response.headers.contentType = ContentType.html;
      request.response.statusCode = 200;
      request.response.write('<html><body><h3>Strava authorization received. You can close this window.</h3></body></html>');
      await request.response.close();
      await server.close(force: true);

      if (code == null) {
        showSnack('No authorization code returned from Strava');
        return;
      }

      final success = await handleAuthCallback(code);
      showSnack(success ? 'Strava connected' : 'Failed to connect to Strava');
      return;
    }

    // Build common query params for mobile platforms
    final params = {
      'client_id': Environment.stravaClientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': 'activity:write,read',
    };

    // Native Strava app deep link attempt first (both platforms)
    final stravaAppUrl = Uri.parse('strava://oauth/mobile/authorize').replace(queryParameters: params);

    // Platform-specific web endpoints
    final webMobileUrl = Uri.parse(_mobileAuthUrl).replace(queryParameters: params); // iOS preferred
    final webStandardUrl = Uri.parse(_authUrl).replace(queryParameters: params);   // Android fallback

    // Strategy:
    // 1. Try native app deep link.
    // 2. If iOS: try in-app webview (mobile auth URL) then external browser.
    // 3. If Android: try external browser directly if native fails.
    bool launched = false;

    // Step 1: Native app
    launched = await _tryLaunch(stravaAppUrl, mode: LaunchMode.externalApplication);

    if (!launched) {
      if (Platform.isIOS) {
        // Step 2 (iOS): in-app webview attempt
        debugPrint('[StravaAuth] Falling back to iOS in-app webview');
        try {
          await launchUrlString(
            webMobileUrl.toString(),
            mode: LaunchMode.inAppWebView,
            webViewConfiguration: const WebViewConfiguration(
              enableJavaScript: true,
              enableDomStorage: true,
            ),
          );
          launched = true;
        } catch (e) {
          debugPrint('[StravaAuth] iOS in-app webview launch failed: $e');
        }
        // If still not launched, final fallback external browser
        if (!launched) {
          debugPrint('[StravaAuth] Falling back to iOS external browser');
          launched = await _tryLaunch(webMobileUrl, mode: LaunchMode.externalApplication);
        }
      } else if (Platform.isAndroid) {
        // Android: go straight to external standard auth endpoint
        debugPrint('[StravaAuth] Falling back to Android external auth');
        launched = await _tryLaunch(webStandardUrl, mode: LaunchMode.externalApplication);
      } else {
        // Other platforms (desktop/web) - try standard URL in external browser
        debugPrint('[StravaAuth] Non-mobile platform fallback to standard URL');
        launched = await _tryLaunch(webStandardUrl, mode: LaunchMode.externalApplication);
      }
    }

    if (!launched) {
      showSnack('Unable to open Strava authorization page');
    }
    return;

    /* Previous implementation retained below for reference (now replaced by unified strategy)
    if (Platform.isIOS) {
      // Try Strava app URL scheme first
      final stravaAppUrl = Uri.parse('strava://oauth/mobile/authorize')
          .replace(queryParameters: {
        'client_id': Environment.stravaClientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'activity:write,read',
      });

      debugPrint('Attempting to launch Strava app URL: ${stravaAppUrl.toString()}');
      
      if (await canLaunchUrl(stravaAppUrl)) {
        await launchUrl(stravaAppUrl);
      } else {
        // Fall back to web OAuth
        final webUrl = Uri.parse(_mobileAuthUrl).replace(queryParameters: {
          'client_id': Environment.stravaClientId,
          'redirect_uri': _redirectUri,
          'response_type': 'code',
          'approval_prompt': 'auto',
          'scope': 'activity:write,read',
        });

        debugPrint('Falling back to web URL: ${webUrl.toString()}');

        await launchUrlString(
          webUrl.toString(),
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
      }
    } else if (Platform.isAndroid) {
      // Try Strava app URL scheme first for Android (similar to iOS)
      final stravaAppUrl = Uri.parse('strava://oauth/mobile/authorize')
          .replace(queryParameters: {
        'client_id': Environment.stravaClientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'activity:write,read',
      });

      debugPrint('Attempting to launch Strava app URL: ${stravaAppUrl.toString()}');
      
      try {
        if (await canLaunchUrl(stravaAppUrl)) {
          await launchUrl(stravaAppUrl);
          return;
        }
      } catch (e) {
        debugPrint('Failed to launch Strava app: $e');
      }

      // Fall back to web OAuth if Strava app is not available
      final webUrl = Uri.parse(_authUrl).replace(queryParameters: {
        'client_id': Environment.stravaClientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'activity:write,read',
      });

      debugPrint('Falling back to web URL: ${webUrl.toString()}');

      await launchUrlString(
        webUrl.toString(),
        mode: LaunchMode.externalApplication,
      );
    }
    */
  }

  // Handle OAuth callback
  static Future<bool> handleAuthCallback(String code) async {
    debugPrint('Handling auth callback with code: $code');
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        body: {
          'client_id': Environment.stravaClientId,
          'client_secret': Environment.stravaClientSecret,
          'code': code,
          'grant_type': 'authorization_code',
        },
      );

      debugPrint('Auth callback response status: ${response.statusCode}');
      debugPrint('Auth callback response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _storeTokens(
          data['access_token'],
          data['refresh_token'],
          data['expires_at'].toString(),
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Auth callback error: $e');
      return false;
    }
  }

  // Upload activity
  static Future<bool> uploadActivity(String filePath, String name, String description) async {
    if (!await isAuthenticated()) return false;

    try {
      final tokens = await getStoredTokens();
      final accessToken = tokens['accessToken'];
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/uploads'),
      );

      request.headers['Authorization'] = 'Bearer $accessToken';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
      ));
      
      request.fields['data_type'] = 'fit';
      request.fields['name'] = name;
      request.fields['description'] = description;

      final response = await request.send();
      debugPrint('Upload response status: ${response.statusCode}');
      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Upload activity error: $e');
      return false;
    }
  }
}

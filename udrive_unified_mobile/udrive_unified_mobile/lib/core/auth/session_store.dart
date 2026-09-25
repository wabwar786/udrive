import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_models.dart';

class SessionStore {
  static const _accessKey = 'phase8_access_token';
  static const _refreshKey = 'phase8_refresh_token';
  static const _accessExpiryKey = 'phase8_access_expiry';
  static const _refreshExpiryKey = 'phase8_refresh_expiry';
  static const _userKey = 'phase8_current_user';
  static const _deviceIdKey = 'phase8_device_id';

  // Browser fallback keys. FlutterSecureStorage on web can occasionally be
  // unavailable after service-worker/browser-storage changes, while the user
  // record in SharedPreferences still makes the UI appear logged in.
  static const _fallbackPrefix = 'udrive_session_fallback_';

  static const Duration _readTimeout = Duration(seconds: 4);
  static const Duration _writeTimeout = Duration(seconds: 8);

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> saveTokens(AuthTokens tokens) async {
    final values = <String, String>{
      _accessKey: tokens.accessToken,
      _refreshKey: tokens.refreshToken,
      _accessExpiryKey: tokens.accessTokenExpiresAt.toIso8601String(),
      _refreshExpiryKey: tokens.refreshTokenExpiresAt.toIso8601String(),
    };

    // Secure storage remains the primary store, but failure there must not
    // prevent a valid login from being persisted in the web app.
    try {
      await Future.wait<void>(
        values.entries.map(
          (entry) => _secure.write(key: entry.key, value: entry.value),
        ),
      ).timeout(_writeTimeout);
    } catch (_) {
      // The SharedPreferences mirror below is the recovery path.
    }

    final prefs = await SharedPreferences.getInstance().timeout(_writeTimeout);
    for (final entry in values.entries) {
      await prefs.setString('$_fallbackPrefix${entry.key}', entry.value);
    }
    await prefs.setString(_userKey, tokens.user.encode());
    await prefs.setBool('loggedIn', true);
  }

  Future<String?> readAccessToken() => _readToken(_accessKey);

  Future<String?> readRefreshToken() => _readToken(_refreshKey);

  Future<DateTime?> readAccessExpiry() async {
    final value = await _readToken(_accessExpiryKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<DateTime?> readRefreshExpiry() async {
    final value = await _readToken(_refreshExpiryKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> saveUser(CurrentUser user) async {
    final prefs = await SharedPreferences.getInstance().timeout(_writeTimeout);
    await prefs.setString(_userKey, user.encode());
  }

  Future<CurrentUser?> readUser() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(_readTimeout);
      return CurrentUser.decode(prefs.getString(_userKey));
    } catch (_) {
      return null;
    }
  }

  Future<String> deviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(_readTimeout);
      var value = prefs.getString(_deviceIdKey);

      if (value == null || value.isEmpty) {
        value = 'udrive-${DateTime.now().microsecondsSinceEpoch}';
        await prefs.setString(_deviceIdKey, value);
      }

      return value;
    } catch (_) {
      return 'udrive-${DateTime.now().microsecondsSinceEpoch}';
    }
  }

  Future<void> clear() async {
    final keys = <String>[
      _accessKey,
      _refreshKey,
      _accessExpiryKey,
      _refreshExpiryKey,
    ];

    await Future.wait<void>(keys.map(_deleteSecureValue));

    try {
      final prefs = await SharedPreferences.getInstance().timeout(_writeTimeout);
      for (final key in keys) {
        await prefs.remove('$_fallbackPrefix$key');
      }
      await prefs.remove(_userKey);
      await prefs.setBool('loggedIn', false);
      await prefs.setString('mode', 'customer');
    } catch (_) {
      // Storage cleanup must never block logout/startup.
    }
  }

  Future<String?> _readToken(String key) async {
    // On Flutter web, SharedPreferences/localStorage is the authoritative
    // session mirror. Some browsers can keep an old encrypted secure-storage
    // value after a service-worker/storage migration even when writes fail.
    // Reading that stale value first causes every authenticated request to use
    // an invalid access/refresh token while the UI still shows the fresh user.
    if (kIsWeb) {
      final browserValue = await _readFallbackValue(key);
      if (browserValue != null) return browserValue;
    }

    try {
      final secureValue = await _secure.read(key: key).timeout(_readTimeout);
      if (secureValue != null && secureValue.isNotEmpty) return secureValue;
    } catch (_) {
      // Fall through to the browser-safe mirror.
    }

    return _readFallbackValue(key);
  }

  Future<String?> _readFallbackValue(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(_readTimeout);
      final fallback = prefs.getString('$_fallbackPrefix$key');
      return fallback == null || fallback.isEmpty ? null : fallback;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSecureValue(String key) async {
    try {
      await _secure.delete(key: key).timeout(_readTimeout);
    } catch (_) {
      // Ignore unavailable or corrupt secure storage.
    }
  }
}

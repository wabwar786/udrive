import 'dart:async';

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

  static const Duration _readTimeout = Duration(seconds: 4);
  static const Duration _writeTimeout = Duration(seconds: 8);

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> saveTokens(AuthTokens tokens) async {
    await Future.wait<void>([
      _secure.write(key: _accessKey, value: tokens.accessToken),
      _secure.write(key: _refreshKey, value: tokens.refreshToken),
      _secure.write(
        key: _accessExpiryKey,
        value: tokens.accessTokenExpiresAt.toIso8601String(),
      ),
      _secure.write(
        key: _refreshExpiryKey,
        value: tokens.refreshTokenExpiresAt.toIso8601String(),
      ),
    ]).timeout(_writeTimeout);

    await saveUser(tokens.user);
  }

  Future<String?> readAccessToken() => _readSecureValue(_accessKey);

  Future<String?> readRefreshToken() => _readSecureValue(_refreshKey);

  Future<DateTime?> readAccessExpiry() async {
    final value = await _readSecureValue(_accessExpiryKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> saveUser(CurrentUser user) async {
    final prefs =
        await SharedPreferences.getInstance().timeout(_writeTimeout);
    await prefs.setString(_userKey, user.encode());
  }

  Future<CurrentUser?> readUser() async {
    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_readTimeout);
      return CurrentUser.decode(prefs.getString(_userKey));
    } catch (_) {
      return null;
    }
  }

  Future<String> deviceId() async {
    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_readTimeout);
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
    await Future.wait<void>([
      _deleteSecureValue(_accessKey),
      _deleteSecureValue(_refreshKey),
      _deleteSecureValue(_accessExpiryKey),
      _deleteSecureValue(_refreshExpiryKey),
    ]);

    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_writeTimeout);
      await prefs.remove(_userKey);
      await prefs.setBool('loggedIn', false);
      await prefs.setString('mode', 'customer');
    } catch (_) {
      // Storage cleanup must never block startup or logout.
    }
  }

  Future<String?> _readSecureValue(String key) async {
    try {
      return await _secure.read(key: key).timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSecureValue(String key) async {
    try {
      await _secure.delete(key: key).timeout(_readTimeout);
    } catch (_) {
      // Ignore unavailable or corrupt browser storage.
    }
  }
}

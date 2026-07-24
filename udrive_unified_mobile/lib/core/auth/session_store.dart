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

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> saveTokens(AuthTokens tokens) async {
    await Future.wait([
      _secure.write(key: _accessKey, value: tokens.accessToken),
      _secure.write(key: _refreshKey, value: tokens.refreshToken),
      _secure.write(key: _accessExpiryKey, value: tokens.accessTokenExpiresAt.toIso8601String()),
      _secure.write(key: _refreshExpiryKey, value: tokens.refreshTokenExpiresAt.toIso8601String()),
    ]);
    await saveUser(tokens.user);
  }

  Future<String?> readAccessToken() => _secure.read(key: _accessKey);
  Future<String?> readRefreshToken() => _secure.read(key: _refreshKey);

  Future<DateTime?> readAccessExpiry() async {
    final value = await _secure.read(key: _accessExpiryKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> saveUser(CurrentUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, user.encode());
  }

  Future<CurrentUser?> readUser() async {
    final prefs = await SharedPreferences.getInstance();
    return CurrentUser.decode(prefs.getString(_userKey));
  }

  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_deviceIdKey);
    if (value == null || value.isEmpty) {
      value = 'udrive-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_deviceIdKey, value);
    }
    return value;
  }

  Future<void> clear() async {
    await Future.wait([
      _secure.delete(key: _accessKey),
      _secure.delete(key: _refreshKey),
      _secure.delete(key: _accessExpiryKey),
      _secure.delete(key: _refreshExpiryKey),
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.setBool('loggedIn', false);
    await prefs.setString('mode', 'customer');
  }
}

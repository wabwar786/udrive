import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/session_store.dart';
import '../network/api_config.dart';

/// Tells the server the app is open, for Admin → App usage.
///
/// Sent when the app starts, when it comes back to the front, and every 30
/// minutes while it is open. It carries the phone model, Android and app
/// version, network type, language, timezone and screen size, plus a random
/// install id kept on the phone. The server adds the IP address and, from it,
/// the city. No GPS, no contacts, no phone number, no IMEI.
///
/// Fire and forget: a failed ping is dropped, never retried, never shown.
class UsagePing with WidgetsBindingObserver {
  UsagePing(this._sessions);

  static const _installKey = 'udrive.install_id';
  static const _flavor = String.fromEnvironment('UDRIVE_FLAVOR', defaultValue: 'play');
  static const _channel = MethodChannel('udrive/device');
  static const _every = Duration(minutes: 30);

  final SessionStore _sessions;
  Timer? _timer;
  Map<String, dynamic>? _device;
  String? _installId;
  DateTime? _lastSent;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(send());
    _timer = Timer.periodic(_every, (_) => unawaited(send()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(send());
  }

  /// Sends one ping. [force] skips the one-minute gap (after sign-in).
  Future<void> send({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSent != null && now.difference(_lastSent!) < const Duration(minutes: 1)) return;
    _lastSent = now;
    try {
      final installId = await _install();
      final device = await _deviceInfo();
      final token = await _sessions.readAccessToken();
      final body = <String, dynamic>{
        'installId': installId,
        'platform': 'android',
        ...device,
        'flavor': _flavor,
        'locale': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
        'timezone': _timezone(now),
        'screen': _screen(),
        'network': await _network(),
      }..removeWhere((_, v) => v == null);
      await http
          .post(
            ApiConfig.uri('/api/v1/telemetry/ping'),
            headers: {
              'Content-Type': 'application/json',
              'X-Install-Id': installId,
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Analytics never gets in the way.
    }
  }

  Future<String> _install() async {
    if (_installId != null) return _installId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_installKey);
    if (id == null || id.length < 8) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_installKey, id);
    }
    return _installId = id;
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    if (_device != null) return _device!;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('info');
      _device = {
        'manufacturer': raw?['manufacturer'],
        'model': raw?['model'],
        'osVersion': raw?['osVersion'],
        'sdk': raw?['sdk'],
        'appVersion': raw?['appVersion'],
        'buildNumber': raw?['buildNumber'],
        'carrier': _text(raw?['carrier']),
      };
    } catch (_) {
      _device = const {};
    }
    return _device!;
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String _timezone(DateTime now) {
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    return '${now.timeZoneName} UTC$sign$hh:$mm';
  }

  static String? _screen() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return null;
    final size = views.first.physicalSize;
    if (size.isEmpty) return null;
    final w = size.width.round();
    final h = size.height.round();
    return w < h ? '${w}x$h' : '${h}x$w';
  }

  static Future<String?> _network() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.wifi)) return 'wifi';
      if (results.contains(ConnectivityResult.mobile)) return 'mobile';
      if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
      if (results.contains(ConnectivityResult.vpn)) return 'vpn';
      return results.contains(ConnectivityResult.none) ? 'offline' : 'other';
    } catch (_) {
      return null;
    }
  }
}

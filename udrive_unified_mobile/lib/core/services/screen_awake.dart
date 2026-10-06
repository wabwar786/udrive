import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Keeps the phone's screen on while a live ride is open.
///
/// UDrive shares the driver's position only while the app is in front — it
/// asks for no background-location permission. A screen that switched off
/// after thirty seconds paused the app, stopped the GPS, and left the
/// customer watching a car that no longer moved.
///
/// Native code in MainActivity.kt and AppDelegate.swift; no package. A count,
/// not a flag, so two live screens briefly open together do not switch it off
/// for each other.
class ScreenAwake {
  const ScreenAwake._();

  static const MethodChannel _channel = MethodChannel('udrive/screen');
  static int _holders = 0;

  static Future<void> hold() async {
    _holders++;
    if (_holders == 1) await _set(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _set(false);
  }

  /// Applies the flag again — Android clears nothing on resume, but a
  /// recreated activity starts without it.
  static Future<void> reapply() async {
    if (_holders > 0) await _set(true);
  }

  static Future<void> _set(bool on) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('keepOn', {'on': on});
    } catch (_) {
      // An older build without the native side: the screen simply times out
      // as before.
    }
  }
}

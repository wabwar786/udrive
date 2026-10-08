import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:udrive_mobile/core/network/api_config.dart';

/// Sends every test step, with a screenshot, to Admin → Live testing.
///
/// It signs in to the API with the Google Play reviewer account (the same
/// number and code the app already carries), so no key or GitHub secret is
/// needed. Optional --dart-define values:
///   TEST_REPORT_URL   API to report to; default API_BASE_URL
///   TEST_SOURCE       e.g. "github #42"
///   TEST_COMMIT       commit SHA
///   TEST_REPORT_KEY   a key from the portal instead of signing in
///
/// If it cannot sign in, the steps still run and print; nothing is sent.
class LiveReporter {
  LiveReporter(this.suite, {required this.phone, required this.code, this.title});

  final String suite;
  final String? title;
  final String phone;
  final String code;

  static const _key = String.fromEnvironment('TEST_REPORT_KEY');
  static const _url = String.fromEnvironment('TEST_REPORT_URL');
  static const _source = String.fromEnvironment('TEST_SOURCE', defaultValue: 'local');
  static const _commit = String.fromEnvironment('TEST_COMMIT');

  String? _runId;
  String? _token;
  int _failed = 0;
  bool _stopped = false;

  bool get hasFailed => _failed > 0;

  Uri _uri(String path) {
    final base = _url.isNotEmpty ? _url : ApiConfig.baseUrl;
    return Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
  }

  Map<String, String> get _headers => {
        if (_key.isNotEmpty) 'X-Test-Key': _key,
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Its own sign-in, separate from the app's, so even the login screens are reported.
  Future<void> _signIn() async {
    final json = {'Content-Type': 'application/json'};
    final request = await http.post(_uri('/api/v1/auth/otp/request'),
        headers: json, body: jsonEncode({'phoneNumber': phone, 'purpose': 'login'}));
    if (request.statusCode >= 300) throw StateError('otp/request ${request.statusCode} ${request.body}');
    final verify = await http.post(_uri('/api/v1/auth/otp/verify'),
        headers: json,
        body: jsonEncode({
          'phoneNumber': phone,
          'code': code,
          'language': 'en',
          'deviceId': 'live-test-reporter',
          'deviceName': 'Live test reporter',
        }));
    final body = jsonDecode(verify.body) as Map<String, dynamic>;
    _token = (body['data'] as Map<String, dynamic>?)?['accessToken'] as String?;
    if (_token == null) throw StateError('otp/verify ${verify.statusCode} ${verify.body}');
  }

  Future<void> start() async {
    try {
      if (_key.isEmpty) await _signIn();
      final response = await http.post(
        _uri('/api/v1/test-runs'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'suite': suite,
          'title': title,
          'source': _source,
          'commitSha': _commit.isEmpty ? null : _commit,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _runId = (body['data'] as Map<String, dynamic>?)?['id'] as String?;
      if (_runId == null) {
        // ignore: avoid_print
        print('[live] could not start a run: ${response.statusCode} ${response.body}');
      }
    } catch (error) {
      // ignore: avoid_print
      print('[live] could not reach the API: $error');
    }
  }

  /// Runs one step: on success "Passed", on an exception "Failed" with the
  /// message. A screenshot of the screen at the end of the step goes with it.
  /// After a failure the remaining steps are reported "Skipped".
  Future<bool> step(
    WidgetTester tester,
    String name,
    Future<void> Function() body, {
    String device = 'customer',
  }) async {
    if (_stopped) {
      await _send(name, 'Skipped', 'pichla qadam fail hua', device, null);
      return false;
    }
    String status = 'Passed';
    String? detail;
    try {
      await body();
    } catch (error) {
      status = 'Failed';
      detail = error.toString().split('\n').take(6).join(' ');
      _failed++;
      _stopped = true;
    }
    final shot = await capture(tester);
    await _send(name, status, detail, device, shot);
    // ignore: avoid_print
    print('[live] ${status.padRight(7)} $name${detail == null ? '' : ' — $detail'}');
    return status == 'Passed';
  }

  /// A note with a screenshot, no pass or fail.
  Future<void> info(WidgetTester tester, String name, {String? detail, String device = 'customer'}) async {
    await _send(name, 'Info', detail, device, await capture(tester));
  }

  Future<void> finish() async {
    if (_runId == null) return;
    try {
      await http.post(
        _uri('/api/v1/test-runs/$_runId/finish'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'status': _failed > 0 ? 'Failed' : 'Passed'}),
      );
    } catch (_) {}
  }

  Future<void> _send(String name, String status, String? detail, String device, List<int>? png) async {
    if (_runId == null) return;
    try {
      final request = http.MultipartRequest('POST', _uri('/api/v1/test-runs/$_runId/steps'))
        ..headers.addAll(_headers)
        ..fields['name'] = name
        ..fields['status'] = status
        ..fields['device'] = device;
      if (detail != null) request.fields['detail'] = detail;
      if (png != null) {
        request.files.add(http.MultipartFile.fromBytes('file', png, filename: 'step.png'));
      }
      await request.send().timeout(const Duration(seconds: 30));
    } catch (_) {
      // A lost report never fails the test.
    }
  }

  /// The Flutter screen as PNG, from the render tree (no platform plug-in).
  static Future<List<int>?> capture(WidgetTester tester) async {
    try {
      await tester.pump();
      return await tester.runAsync<List<int>?>(() async {
        final view = tester.binding.renderViews.first;
        final layer = view.debugLayer;
        if (layer is! OffsetLayer) return null;
        final ratio = view.flutterView.devicePixelRatio.clamp(1.0, 2.0);
        final image = await layer.toImage(Offset.zero & view.size, pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data?.buffer.asUint8List();
      });
    } catch (_) {
      return null;
    }
  }
}

/// Pumps until [finder] shows up (or [timeout]); pumpAndSettle never settles
/// on screens with a map or a spinner.
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Screen par nahi mila. Screen par likha hai: ${screenTexts()}');
}

/// The words on the screen right now, to say where a step got stuck.
String screenTexts() {
  final texts = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final t = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
    if (t.isNotEmpty && !texts.contains(t)) texts.add(t);
    if (texts.length >= 25) break;
  }
  return texts.join(' | ');
}

/// Pumps for [duration] without waiting for animations to stop.
Future<void> settle(WidgetTester tester, [Duration duration = const Duration(seconds: 2)]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

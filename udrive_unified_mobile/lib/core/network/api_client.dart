import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../models/auth_models.dart';
import '../auth/session_store.dart';
import 'api_config.dart';

class ApiClient {
  ApiClient(this.sessionStore, {http.Client? client})
      : _client = client ?? http.Client();

  final SessionStore sessionStore;
  final http.Client _client;

  // Refresh tokens are rotated by the API. This future must be shared by every
  // ApiClient instance; otherwise repositories can refresh simultaneously and
  // invalidate each other's newly-issued token.
  static Future<bool>? _sharedRefreshFuture;

  Future<Map<String, dynamic>> getJson(
    String path, {
    bool authenticated = true,
  }) =>
      _jsonRequest('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) =>
      _jsonRequest(
        'POST',
        path,
        body: body,
        authenticated: authenticated,
      );

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) =>
      _jsonRequest(
        'PUT',
        path,
        body: body,
        authenticated: authenticated,
      );

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String fieldName,
    required PlatformFile file,
    required Map<String, String> fields,
  }) async {
    http.MultipartRequest buildRequest(String? token) {
      final request = http.MultipartRequest('POST', ApiConfig.uri(path));
      request.fields.addAll(fields);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      return request;
    }

    Future<void> addFile(http.MultipartRequest request) async {
      if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            fieldName,
            file.bytes!,
            filename: file.name,
          ),
        );
      } else if (file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            file.path!,
            filename: file.name,
          ),
        );
      } else {
        throw const ApiException('The selected file could not be read.');
      }
    }

    final token = await sessionStore.readAccessToken();
    var request = buildRequest(token);
    await addFile(request);

    /// Sends the request and turns transport failures into something readable.
    ///
    /// On the web, a request the browser refuses — a blocked origin, a
    /// response it cannot read, a connection cut mid-upload — arrives here as
    /// `ClientException: Load failed`, which is Safari's wording and tells the
    /// person nothing. An upload is also the one request most likely to hit a
    /// slow connection, so the timeout is worth naming separately.
    Future<http.Response> send(http.MultipartRequest built) async {
      try {
        return await http.Response.fromStream(
          await built.send().timeout(const Duration(seconds: 90)),
        );
      } on TimeoutException {
        throw const ApiException(
          'The upload timed out. Check your connection and try again — a '
          'smaller photograph will send faster.',
        );
      } on http.ClientException catch (error) {
        throw ApiException(
          'The upload could not reach the server (${error.message}). '
          'Check your connection, then try again.',
        );
      }
    }

    var response = await send(request);

    if (response.statusCode == 401 && await _tryRefresh()) {
      final freshToken = await sessionStore.readAccessToken();
      request = buildRequest(freshToken);
      await addFile(request);
      response = await send(request);
    }

    return _decode(response);
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authenticated,
    bool allowRefresh = true,
  }) async {
    if (authenticated && allowRefresh) {
      final accessToken = await sessionStore.readAccessToken();
      final expiry = await sessionStore.readAccessExpiry();

      // An older session may not have expiry metadata. Do not discard a token
      // merely because metadata is absent; send it and refresh only if the API
      // actually returns 401.
      final missingToken = accessToken == null || accessToken.isEmpty;
      final expiringSoon = expiry != null &&
          expiry.isBefore(DateTime.now().add(const Duration(seconds: 45)));

      if (missingToken || expiringSoon) {
        await _tryRefresh();
      }
    }

    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';

    if (authenticated) {
      final token = await sessionStore.readAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final uri = ApiConfig.uri(path);
    late http.Response response;

    if (method == 'GET') {
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    } else if (method == 'PUT') {
      response = await _client
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
    } else {
      response = await _client
          .post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    }

    if (authenticated &&
        allowRefresh &&
        response.statusCode == 401 &&
        await _tryRefresh()) {
      return _jsonRequest(
        method,
        path,
        body: body,
        authenticated: true,
        allowRefresh: false,
      );
    }

    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json = <String, dynamic>{};

    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          json = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        throw ApiException(
          response.statusCode >= 500
              ? 'The Udrive service is temporarily unavailable.'
              : 'The server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        json['message']?.toString() ??
            json['detail']?.toString() ??
            'The request could not be completed.',
        statusCode: response.statusCode,
        code: json['error']?.toString(),
      );
    }

    return json;
  }

  Future<bool> _tryRefresh() {
    final running = _sharedRefreshFuture;
    if (running != null) return running;

    final future = _performRefresh();
    _sharedRefreshFuture = future;

    return future.whenComplete(() {
      if (identical(_sharedRefreshFuture, future)) {
        _sharedRefreshFuture = null;
      }
    });
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await sessionStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final deviceId = await sessionStore.deviceId();
      final response = await _jsonRequest(
        'POST',
        '/api/v1/auth/refresh',
        authenticated: false,
        allowRefresh: false,
        body: {
          'refreshToken': refreshToken,
          'deviceId': deviceId,
          'deviceName': 'Udrive mobile',
        },
      );

      final rawData = response['data'];
      if (rawData is! Map) return false;

      await sessionStore.saveTokens(
        AuthTokens.fromJson(Map<String, dynamic>.from(rawData)),
      );
      return true;
    } on ApiException catch (error) {
      // Only a definitive token rejection invalidates the local session.
      // Network/5xx failures must leave the completed booking form intact.
      if (error.statusCode == 400 || error.statusCode == 401) {
        await sessionStore.clear();
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

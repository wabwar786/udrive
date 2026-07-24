import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../auth/session_store.dart';
import '../../models/auth_models.dart';
import 'api_config.dart';

class ApiClient {
  ApiClient(this.sessionStore, {http.Client? client}) : _client = client ?? http.Client();

  final SessionStore sessionStore;
  final http.Client _client;
  bool _refreshing = false;

  Future<Map<String, dynamic>> getJson(String path, {bool authenticated = true}) =>
      _jsonRequest('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) =>
      _jsonRequest('POST', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) =>
      _jsonRequest('PUT', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String fieldName,
    required PlatformFile file,
    required Map<String, String> fields,
  }) async {
    final request = http.MultipartRequest('POST', ApiConfig.uri(path));
    request.fields.addAll(fields);
    final token = await sessionStore.readAccessToken();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    if (file.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes(fieldName, file.bytes!, filename: file.name));
    } else if (file.path != null) {
      request.files.add(await http.MultipartFile.fromPath(fieldName, file.path!, filename: file.name));
    } else {
      throw const ApiException('The selected file could not be read.');
    }

    var response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 401 && await _tryRefresh()) {
      final retry = http.MultipartRequest('POST', ApiConfig.uri(path));
      retry.fields.addAll(fields);
      final fresh = await sessionStore.readAccessToken();
      if (fresh != null) retry.headers['Authorization'] = 'Bearer $fresh';
      if (file.bytes != null) {
        retry.files.add(http.MultipartFile.fromBytes(fieldName, file.bytes!, filename: file.name));
      } else {
        retry.files.add(await http.MultipartFile.fromPath(fieldName, file.path!, filename: file.name));
      }
      response = await http.Response.fromStream(await retry.send());
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
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authenticated) {
      final token = await sessionStore.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    final uri = ApiConfig.uri(path);
    late http.Response response;
    if (method == 'GET') {
      response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } else if (method == 'PUT') {
      response = await _client.put(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
    } else {
      response = await _client.post(uri, headers: headers, body: body == null ? null : jsonEncode(body)).timeout(const Duration(seconds: 25));
    }

    if (authenticated && allowRefresh && response.statusCode == 401 && await _tryRefresh()) {
      return _jsonRequest(method, path, body: body, authenticated: true, allowRefresh: false);
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw ApiException(
          response.statusCode >= 500 ? 'The uDrive service is temporarily unavailable.' : 'The server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        json['message']?.toString() ?? json['detail']?.toString() ?? 'The request could not be completed.',
        statusCode: response.statusCode,
        code: json['error']?.toString(),
      );
    }
    return json;
  }

  Future<bool> _tryRefresh() async {
    if (_refreshing) return false;
    final refreshToken = await sessionStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    _refreshing = true;
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
          'deviceName': 'uDrive mobile',
        },
      );
      final data = response['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      await sessionStore.saveTokens(AuthTokens.fromJson(data));
      return true;
    } catch (_) {
      await sessionStore.clear();
      return false;
    } finally {
      _refreshing = false;
    }
  }
}

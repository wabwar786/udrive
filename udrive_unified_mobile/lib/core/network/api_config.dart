abstract final class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://udrive-api-production.up.railway.app',
  );

  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);
    final normalized = path.startsWith('/') ? path : '/$path';
    final values = query?.map((key, value) => MapEntry(key, value?.toString()));
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$normalized',
      queryParameters: values?.cast<String, String?>(),
    );
  }

  static String absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return uri(path).toString();
  }
}

abstract final class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://udrive-api-production.up.railway.app',
  );

  /// Builds an absolute URL from a path and optional query parameters.
  ///
  /// The path may already carry its own query string —
  /// `'/api/v1/thing?a=1&b=2'`. That has to be split out before the rest is
  /// treated as a path, because `Uri.replace(path: …)` percent-encodes
  /// everything it is given: a `?` left in the path becomes `%3F`, the server
  /// sees it as part of the route, and the request 404s with the parameters
  /// silently glued to the endpoint name.
  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);

    final separator = path.indexOf('?');
    final pathOnly = separator >= 0 ? path.substring(0, separator) : path;
    final inlineQuery = separator >= 0 ? path.substring(separator + 1) : '';

    final normalized = pathOnly.startsWith('/') ? pathOnly : '/$pathOnly';

    final values = <String, String?>{
      if (inlineQuery.isNotEmpty) ...Uri.splitQueryString(inlineQuery),
      if (query != null)
        for (final entry in query.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
    };

    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}${normalized}',
      queryParameters: values.isEmpty ? null : values,
    );
  }

  static String absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return uri(path).toString();
  }
}

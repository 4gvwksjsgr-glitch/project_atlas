// ignore_for_file: deprecated_member_use

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Rimuove i parametri auth dall'URL del browser preservando l'hash route.
void clearAuthUriParams() {
  final currentUri = Uri.parse(html.window.location.href);
  const authParameters = {
    'code',
    'access_token',
    'error',
    'error_code',
    'error_description',
    'type',
  };

  final query = Map<String, List<String>>.of(currentUri.queryParametersAll)
    ..removeWhere((key, value) => authParameters.contains(key));

  final cleanedUri = Uri(
    scheme: currentUri.scheme,
    host: currentUri.host,
    port: currentUri.hasPort ? currentUri.port : null,
    path: currentUri.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: currentUri.fragment.isEmpty ? null : currentUri.fragment,
  );

  html.window.history.replaceState(null, '', cleanedUri.toString());
}

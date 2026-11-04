import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
/// The API address is passed at build time:
/// `flutter run --dart-define=API_URL=https://api.vixeo.app`
/// (Android emulator talking to a local API: `http://10.0.2.2:8000`).
class AppConfig {
  const AppConfig._();

  static const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

  static const bool _apiUrlGiven = bool.hasEnvironment('API_URL');

  /// Why this build must not start, or null. A release build needs an explicit `https://` API
  /// (plain `http://` only to this machine or the Android emulator's host, for local tests).
  static String? get configurationError => checkApiUrl(apiUrl, given: _apiUrlGiven, release: kReleaseMode);

  @visibleForTesting
  static String? checkApiUrl(String url, {required bool given, required bool release}) {
    if (!release) return null;
    if (!given) return 'Adresse de l’API manquante : compilez avec --dart-define=API_URL=https://…';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'Adresse de l’API invalide : $url';
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && _localHosts.contains(uri.host)) return null;
    return 'L’API doit être en https:// (adresse reçue : $url).';
  }

  static const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  /// Base URL of the v1 API, e.g. `https://api.vixeo.app/api/v1`.
  static String get apiBase => '${apiUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1';

  /// Mandatory TMDb notice (shown in "À propos").
  static const String tmdbAttribution = 'This product uses the TMDB API but is not endorsed or certified by TMDB.';
}

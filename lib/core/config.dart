import 'package:flutter/foundation.dart';

import 'legal.dart';

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
  static String? get configurationError =>
      checkApiUrl(apiUrl, given: _apiUrlGiven, release: kReleaseMode) ??
      checkLegal(publisher: Legal.publisher, supportEmail: Legal.supportEmail, release: kReleaseMode);

  /// A published app names its publisher and a support address.
  @visibleForTesting
  static String? checkLegal({required String publisher, required String supportEmail, required bool release}) {
    if (!release) return null;
    if (publisher.trim().isEmpty || !supportEmail.contains('@')) {
      return 'Éditeur ou adresse de support manquants : compilez avec '
          '--dart-define=PUBLISHER_NAME=… --dart-define=SUPPORT_EMAIL=…';
    }
    return null;
  }

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
}

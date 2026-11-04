/// Build-time configuration.
///
/// The API address is passed at build time:
/// `flutter run --dart-define=API_URL=https://api.vixeo.app`
/// (Android emulator talking to a local API: `http://10.0.2.2:8000`).
class AppConfig {
  const AppConfig._();

  static const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

  /// Base URL of the v1 API, e.g. `https://api.vixeo.app/api/v1`.
  static String get apiBase => '${apiUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1';

  /// Mandatory TMDb notice (shown in "À propos").
  static const String tmdbAttribution = 'This product uses the TMDB API but is not endorsed or certified by TMDB.';
}

/// Who publishes Vixeo and how to reach them: shown in the privacy policy and "Aide et à propos".
///
/// Passed at build time, like `API_URL`:
/// `--dart-define=PUBLISHER_NAME="…" --dart-define=SUPPORT_EMAIL=support@…`.
/// A release build refuses to start without them (no placeholder in a published app).
class Legal {
  const Legal._();

  /// Person or company responsible for the app and its data (GDPR "responsable du traitement").
  static const publisher = String.fromEnvironment('PUBLISHER_NAME');

  /// Support and privacy requests.
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

  /// Last change of the privacy policy (update it with the text).
  static const privacyPolicyDate = '4 novembre 2026';

  static String get publisherOrDefault => publisher.isEmpty ? 'L’éditeur de Vixeo' : publisher;
}

/// Who publishes Vixeo and how to reach them (support address on "Mise à jour nécessaire").
///
/// Passed at build time, like `API_URL`:
/// `--dart-define=PUBLISHER_NAME="…" --dart-define=SUPPORT_EMAIL=support@…`.
/// A release build refuses to start without them (no placeholder in a published app).
class Legal {
  const Legal._();

  /// Person or company responsible for the app and its data (GDPR "responsable du traitement").
  static const publisher = String.fromEnvironment('PUBLISHER_NAME');

  /// Support requests.
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}

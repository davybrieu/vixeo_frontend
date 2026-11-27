import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/config.dart';
import 'models.dart';
import 'session.dart';
import 'social_sign_in.dart';

/// Sends an email link, waits for its one-time PKCE callback, then exchanges it for a session.
Future<({String token, User user})?> signInWithEmail(
  WidgetRef ref, {
  required String email,
  String? name,
  String? username,
}) async {
  final authorizer = ref.read(browserAuthorizerProvider);
  if (authorizer == null) {
    throw ApiException('La connexion par e-mail n’est pas disponible sur cet appareil.');
  }

  final verifier = pkceVerifier();
  final redirect = await authorizer.prepare();
  final repository = ref.read(authRepositoryProvider);

  await repository.requestEmailLink(
    email: email,
    redirectUri: '$redirect',
    challenge: pkceChallenge(verifier),
  );

  final back = await authorizer.authorize(Uri.parse('${AppConfig.apiBase}/auth/email/waiting'));
  if (back == null) return null;
  final code = back.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw ApiException('Le lien de connexion n’a pas abouti. Demandez-en un nouveau.');
  }

  return repository.emailToken(code: code, verifier: verifier);
}

/// Confirms a new account e-mail address through its one-time link, then exchanges the PKCE code.
Future<({String token, User user})?> changeEmailWithLink(
  WidgetRef ref, {
  required String email,
}) async {
  final authorizer = ref.read(browserAuthorizerProvider);
  if (authorizer == null) {
    throw ApiException('La confirmation d’adresse e-mail n’est pas disponible sur cet appareil.');
  }

  final verifier = pkceVerifier();
  final redirect = await authorizer.prepare();
  await ref.read(authRepositoryProvider).updateEmail(
    email: email,
    redirectUri: '$redirect',
    challenge: pkceChallenge(verifier),
  );

  final back = await authorizer.authorize(Uri.parse('${AppConfig.apiBase}/auth/email/waiting'));
  if (back == null) return null;
  final code = back.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw ApiException('Le lien de confirmation n’a pas abouti. Demandez-en un nouveau.');
  }

  return ref.read(authRepositoryProvider).emailToken(code: code, verifier: verifier);
}

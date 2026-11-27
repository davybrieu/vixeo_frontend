import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/api/api_exception.dart';
import '../../core/config.dart';
import '../../core/device/layout.dart';
import 'session.dart';

/// « Continuer avec Google / Apple » (vixeo_backend/docs/connexion-sociale.md).
///
/// The sign-in runs in a browser, like most apps (RFC 8252): a Chrome tab on Android, the default
/// browser on Windows. The API talks to Google and Apple (the app has none of their settings),
/// then sends the browser back to the app with a code; the app trades it for its token with a
/// secret it kept (PKCE), so a code caught by someone else is useless.
enum SocialProvider {
  google('Google'),
  apple('Apple');

  const SocialProvider(this.label);

  /// « Continuer avec Google ».
  final String label;
}

/// Where the browser comes back on Android and iOS: the app's scheme (the `CallbackActivity` of
/// flutter_web_auth_2 in AndroidManifest.xml).
const appRedirect = 'app.vixeo://auth';

/// Opens the sign-in page in a browser and waits for the browser to come back to the app.
abstract class BrowserAuthorizer {
  /// Where the browser must come back (Windows: starts the app's little server).
  Future<Uri> prepare();

  /// Opens [url] and waits: the address the browser came back to, null when the person gave up.
  Future<Uri?> authorize(Uri url);

  /// Stops waiting ([authorize] gives null).
  void cancel();
}

/// The browser of this device, or null where the sign-in with Google and Apple isn't offered (TV:
/// it signs in with a code; the tests, unless they give theirs).
final browserAuthorizerProvider = Provider<BrowserAuthorizer?>((ref) {
  if (kIsWeb || DeviceInfo.isTv) return null;
  if (Platform.isAndroid || Platform.isIOS) return CustomTabAuthorizer();
  if (Platform.isWindows) return LoopbackAuthorizer();
  return null;
});

/// Whether the server has the settings of each provider (`GET /auth/social`): a provider without
/// them says so at once, without opening the browser.
final socialProvidersProvider = FutureProvider<Map<SocialProvider, bool>>((ref) async {
  final available = await ref.read(authRepositoryProvider).socialProviders();
  return {for (final provider in SocialProvider.values) provider: available[provider.name] ?? false};
});

/// What a sign-in gave: [signedIn] (the router moves on), and a sentence to show, if any.
class SocialSignInResult {
  const SocialSignInResult({required this.signedIn, this.message, this.registrationTicket});

  final bool signedIn;
  final String? message;
  final String? registrationTicket;
}

/// Signs in with [provider]: the browser, then the token. Throws [ApiException] when the API
/// refuses the code.
Future<SocialSignInResult> signInWith(WidgetRef ref, SocialProvider provider) async {
  final authorizer = ref.read(browserAuthorizerProvider);
  if (authorizer == null) return const SocialSignInResult(signedIn: false);

  final verifier = pkceVerifier();
  final redirect = await authorizer.prepare();
  final start = Uri.parse('${AppConfig.apiBase}/auth/social/${provider.name}').replace(
    queryParameters: {
      'redirect_uri': '$redirect',
      'code_challenge': pkceChallenge(verifier),
      'code_challenge_method': 'S256',
    },
  );

  final Uri? back;
  try {
    back = await authorizer.authorize(start);
  } on PlatformException {
    return const SocialSignInResult(signedIn: false, message: 'Le navigateur n’a pas pu s’ouvrir. Réessayez.');
  }
  if (back == null) return const SocialSignInResult(signedIn: false);

  final error = back.queryParameters['error'];
  final code = back.queryParameters['code'];
  if (error != null || code == null || code.isEmpty) {
    return SocialSignInResult(signedIn: false, message: socialSignInError(provider, error ?? 'failed'));
  }

  final result = await ref.read(authRepositoryProvider).socialToken(code: code, verifier: verifier);
  if (result.registrationTicket != null) {
    return SocialSignInResult(signedIn: false, registrationTicket: result.registrationTicket);
  }
  final token = result.token;
  final user = result.user;
  if (token == null || user == null) throw const ApiException('Réponse de connexion invalide.');
  await ref.read(sessionProvider.notifier).signInWithToken(token, user);
  return const SocialSignInResult(signedIn: true);
}

/// The sentence of an `?error=` the browser came back with (`cancelled`: none).
String? socialSignInError(SocialProvider provider, String reason) => switch (reason) {
  'cancelled' => null,
  'unavailable' => 'La connexion avec ${provider.label} n’est pas encore disponible.',
  'email' => '${provider.label} n’a pas donné d’adresse e-mail : le compte ne peut pas être créé.',
  'unverified' =>
    '${provider.label} n’a pas vérifié cette adresse : connectez-vous avec votre e-mail et votre mot de passe.',
  _ => '${provider.label} n’a pas pu vous connecter. Réessayez.',
};

/// A PKCE secret (RFC 7636): 64 random characters of base64url.
String pkceVerifier() {
  final random = Random.secure();
  return base64UrlEncode([for (var i = 0; i < 48; i++) random.nextInt(256)]).replaceAll('=', '');
}

/// Its S256 challenge: base64url of its SHA-256, without padding.
String pkceChallenge(String verifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

/// Android (a Chrome tab: Custom Tab, or Auth Tab) and iOS (ASWebAuthenticationSession).
class CustomTabAuthorizer implements BrowserAuthorizer {
  @override
  Future<Uri> prepare() async => Uri.parse(appRedirect);

  @override
  Future<Uri?> authorize(Uri url) async {
    try {
      return Uri.parse(await FlutterWebAuth2.authenticate(url: '$url', callbackUrlScheme: 'app.vixeo'));
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      rethrow;
    }
  }

  @override
  void cancel() {}
}

/// Windows: the default browser, which comes back to a little server of the app on the device
/// itself (`http://127.0.0.1:{port}/auth`, a port the system picks), then Vixeo comes to the front.
class LoopbackAuthorizer implements BrowserAuthorizer {
  HttpServer? _server;
  Completer<Uri?>? _back;

  /// How long the browser has to come back.
  static const timeout = Duration(minutes: 10);

  @override
  Future<Uri> prepare() async {
    await _server?.close(force: true);
    final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return Uri.parse('http://127.0.0.1:${server.port}/auth');
  }

  @override
  Future<Uri?> authorize(Uri url) async {
    final server = _server;
    if (server == null) throw StateError('prepare() first');
    final back = _back = Completer<Uri?>();
    server.listen((request) async {
      if (request.uri.path != '/auth') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(_landingPage);
      await request.response.close();
      if (!back.isCompleted) back.complete(request.uri);
    });

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw PlatformException(code: 'BROWSER', message: 'No browser.');
      }
      final result = await back.future.timeout(timeout, onTimeout: () => null);
      if (result != null) {
        // The browser is in front: Vixeo comes back.
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
      }
      return result;
    } finally {
      await server.close(force: true);
      if (identical(_server, server)) _server = null;
    }
  }

  @override
  void cancel() {
    final back = _back;
    if (back != null && !back.isCompleted) back.complete(null);
  }

  static const _landingPage = '''<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vixeo</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#070A08;color:#F1F5F2;
font-family:system-ui,"Segoe UI",sans-serif;text-align:center}main{padding:32px;max-width:420px}
h1{font-size:22px;margin:0 0 12px}p{color:#A9B3AC;line-height:1.5;margin:0}</style></head>
<body><main><h1>C’est fait</h1><p>Vous pouvez fermer cet onglet et revenir dans Vixeo.</p></main></body></html>''';
}

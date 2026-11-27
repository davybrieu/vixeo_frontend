import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/login_screen.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/auth/social_sign_in.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository() : super(ApiClient(token: () => null));
  String? requestedEmail;
  String? redirectUri;
  String? challenge;
  String? redeemedCode;
  String? redeemedVerifier;

  @override
  Future<String> requestEmailLink({required String email, required String redirectUri, required String challenge}) async {
    requestedEmail = email;
    this.redirectUri = redirectUri;
    this.challenge = challenge;
    return 'Si un compte utilise cette adresse, un lien vient de lui être envoyé.';
  }

  @override
  Future<({String token, User user})> emailToken({required String code, required String verifier}) async {
    redeemedCode = code;
    redeemedVerifier = verifier;
    return (token: 'token-email', user: const User(id: 1, name: 'Davy', email: 'davy@exemple.fr'));
  }

  @override
  Future<List<Profile>> profiles() async => const [];

  @override
  Future<Map<String, bool>> socialProviders() async => {'google': true, 'apple': false};

  @override
  Future<({String token, User user, bool created})> socialToken({required String code, required String verifier}) async =>
      (token: 'token-social', user: const User(id: 2, name: 'Léa', email: 'lea@gmail.com'), created: true);
}

class SignedOut extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedOut);
}

class FakeBrowser implements BrowserAuthorizer {
  FakeBrowser(this.back);
  Uri? back;
  Uri? opened;

  @override
  Future<Uri> prepare() async => Uri.parse(appRedirect);
  @override
  Future<Uri?> authorize(Uri url) async { opened = url; return back; }
  @override
  void cancel() {}
}

void main() {
  late FakeAuthRepository auth;
  late MemorySessionStorage storage;
  late ProviderContainer container;
  late FakeBrowser browser;

  setUp(() {
    auth = FakeAuthRepository();
    storage = MemorySessionStorage();
    browser = FakeBrowser(Uri.parse('app.vixeo://auth?code=email-code'));
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      sessionStorageProvider.overrideWithValue(storage),
      browserAuthorizerProvider.overrideWithValue(browser),
      sessionProvider.overrideWith(SignedOut.new),
    ]);
  });

  tearDown(() => container.dispose());

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildVixeoTheme(), home: page),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('welcome page offers social sign-in and email sign-in', (tester) async {
    await pumpPage(tester, const LoginScreen());
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsOneWidget);
    expect(find.text('Continuer avec l’e-mail'), findsOneWidget);
  });

  testWidgets('email sign-in sends a link, waits for its callback and redeems the PKCE code', (tester) async {
    await pumpPage(tester, const EmailLoginScreen());
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.textContaining('lien de connexion valable 15 minutes'), findsOneWidget);
    expect(find.text('Mot de passe oublié ?'), findsNothing);
    expect(find.text('Mot de passe'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '  davy@exemple.fr ');
    await tester.tap(find.text('Envoyer le lien de connexion'));
    await tester.pumpAndSettle();

    expect(auth.requestedEmail, 'davy@exemple.fr');
    expect(auth.redirectUri, appRedirect);
    expect(auth.challenge, isNotNull);
    expect(browser.opened?.path, endsWith('/auth/email/waiting'));
    expect(auth.redeemedCode, 'email-code');
    expect(auth.redeemedVerifier, isNotNull);
    expect(auth.challenge, pkceChallenge(auth.redeemedVerifier!));
    expect(container.read(sessionProvider).isSignedIn, isTrue);
    expect(storage.token, 'token-email');
  });

  testWidgets('invalid email is rejected before sending a link', (tester) async {
    await pumpPage(tester, const EmailLoginScreen());
    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Envoyer le lien de connexion'));
    await tester.pumpAndSettle();

    expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
    expect(auth.requestedEmail, isNull);
  });
}

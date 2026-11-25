import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/login_screen.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/auth/social_sign_in.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository() : super(ApiClient(token: () => null, profileId: () => null));

  String? lastEmail;

  @override
  Future<({String token, User user})> login({required String email, required String password}) async {
    lastEmail = email;
    if (password != 'secret-password') {
      throw const ApiException(
        'Adresse e-mail ou mot de passe incorrect.',
        status: 422,
        fieldErrors: {
          'email': ['Adresse e-mail ou mot de passe incorrect.'],
        },
      );
    }
    return (token: 'token-1', user: const User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false));
  }

  Map<String, bool> available = {'google': true, 'apple': false};
  final tokens = <({String code, String verifier})>[];
  bool passwordRemoved = false;

  @override
  Future<Map<String, bool>> socialProviders() async => available;

  @override
  Future<({String token, User user, bool created, bool passwordRemoved})> socialToken({
    required String code,
    required String verifier,
  }) async {
    tokens.add((code: code, verifier: verifier));
    return (
      token: 'token-google',
      user: const User(id: 2, name: 'Léa', email: 'lea@gmail.com', parentalControl: false, hasPassword: false),
      created: true,
      passwordRemoved: passwordRemoved,
    );
  }
}

/// The browser: gives back [back] (null: the person gave up), and keeps the address it opened.
class FakeBrowser implements BrowserAuthorizer {
  FakeBrowser(this.back);

  Uri? back;
  Uri? opened;

  @override
  Future<Uri> prepare() async => Uri.parse(appRedirect);

  @override
  Future<Uri?> authorize(Uri url) async {
    opened = url;
    return back;
  }

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
    browser = FakeBrowser(Uri.parse('app.vixeo://auth?code=browser-code'));
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sessionStorageProvider.overrideWithValue(storage),
        browserAuthorizerProvider.overrideWithValue(browser),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildVixeoTheme(), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpLogin(WidgetTester tester) => pumpPage(tester, const EmailLoginScreen());

  testWidgets('the welcome page: a tagline, then Google, Apple and the e-mail', (tester) async {
    await pumpPage(tester, const LoginScreen());

    expect(find.textContaining('Partagez vos avis avec la communauté'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsOneWidget);
    expect(find.text('Continuer avec l’e-mail'), findsOneWidget);
    expect(find.text('Continuer en invité'), findsNothing);
    expect(find.textContaining('que votre nom et votre adresse e-mail'), findsOneWidget);
  });

  testWidgets('Google: the browser, then the token with the secret of the challenge', (tester) async {
    await pumpPage(tester, const LoginScreen());

    await tester.tap(find.text('Continuer avec Google'));
    await tester.pumpAndSettle();

    final opened = browser.opened!;
    expect(opened.path, endsWith('/api/v1/auth/social/google'));
    expect(opened.queryParameters['redirect_uri'], 'app.vixeo://auth');
    expect(opened.queryParameters['code_challenge_method'], 'S256');
    final token = auth.tokens.single;
    expect(token.code, 'browser-code');
    // The secret stayed in the app; the browser only had its hash.
    expect(opened.queryParameters['code_challenge'], pkceChallenge(token.verifier));
    expect(opened.toString(), isNot(contains(token.verifier)));
    expect(container.read(sessionProvider).isSignedIn, isTrue);
    expect(storage.token, 'token-google');
  });

  testWidgets('Apple without settings on the server: said at once, without the browser', (tester) async {
    await pumpPage(tester, const LoginScreen());

    await tester.tap(find.text('Continuer avec Apple'));
    await tester.pump();

    expect(find.text('La connexion avec Apple n’est pas encore disponible.'), findsOneWidget);
    expect(browser.opened, isNull);
  });

  testWidgets('an error the browser comes back with, and nothing when the person gives up', (tester) async {
    await pumpPage(tester, const LoginScreen());

    browser.back = Uri.parse('app.vixeo://auth?error=unverified');
    await tester.tap(find.text('Continuer avec Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Google n’a pas vérifié cette adresse'), findsOneWidget);
    expect(container.read(sessionProvider).isSignedIn, isFalse);

    ScaffoldMessenger.of(tester.element(find.byType(LoginScreen))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    browser.back = null;
    await tester.tap(find.text('Continuer avec Google'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(auth.tokens, isEmpty);
  });

  testWidgets('says when the password of the account was removed', (tester) async {
    auth.passwordRemoved = true;
    await pumpPage(tester, const LoginScreen());

    await tester.tap(find.text('Continuer avec Google'));
    await tester.pumpAndSettle();

    expect(find.textContaining('l’ancien mot de passe de ce compte a été retiré'), findsOneWidget);
  });

  testWidgets('no Google nor Apple without a browser (a TV): the e-mail only', (tester) async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sessionStorageProvider.overrideWithValue(storage),
        browserAuthorizerProvider.overrideWithValue(null),
      ],
    );
    await pumpPage(tester, const LoginScreen());

    expect(find.text('Continuer avec Google'), findsNothing);
    expect(find.text('Continuer avec Apple'), findsNothing);
    expect(find.text('Continuer avec l’e-mail'), findsOneWidget);
  });

  testWidgets('asks for the e-mail and the password', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Saisissez votre adresse e-mail.'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
    expect(auth.lastEmail, isNull);
  });

  testWidgets('shows the API error under the e-mail field', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'davy@exemple.fr');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Adresse e-mail ou mot de passe incorrect.'), findsOneWidget);
    expect(container.read(sessionProvider).isSignedIn, isFalse);
  });

  testWidgets('signs in and keeps the token', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byType(TextFormField).at(0), '  davy@exemple.fr ');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(auth.lastEmail, 'davy@exemple.fr');
    expect(container.read(sessionProvider).isSignedIn, isTrue);
    expect(container.read(sessionProvider).user?.name, 'Davy');
    expect(storage.token, 'token-1');
  });

  testWidgets('shows or hides the password', (tester) async {
    await pumpLogin(tester);

    expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
    await tester.tap(find.byTooltip('Afficher le mot de passe'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
  });
}

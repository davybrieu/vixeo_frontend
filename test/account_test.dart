import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/account/account_screen.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/auth/social_sign_in.dart';

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr');

class FakeAccountAuth extends AuthRepository {
  FakeAccountAuth() : super(ApiClient(token: () => null));
  final calls = <String>[];

  @override
  Future<String> updateEmail({required String email, required String redirectUri, required String challenge}) async {
    calls.add('email $email');
    return 'Un lien de confirmation a été envoyé.';
  }

  @override
  Future<({String token, User user})> emailToken({required String code, required String verifier}) async {
    calls.add('redeem $code');
    return (token: 'new-token', user: User(id: davy.id, name: davy.name, email: 'nouveau@exemple.fr'));
  }

  @override
  Future<void> deleteAccount() async => calls.add('delete');

  @override
  Future<String> exportData() async {
    calls.add('export');
    return 'Vos données ont été envoyées à davy@exemple.fr.';
  }
}

class FakeBrowser implements BrowserAuthorizer {
  @override
  Future<Uri> prepare() async => Uri.parse('app.vixeo://auth');
  @override
  Future<Uri?> authorize(Uri url) async => Uri.parse('app.vixeo://auth?code=change-code');
  @override
  void cancel() {}
}

class SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedIn, token: 't', user: davy);
}

(ProviderContainer, FakeAccountAuth, MemorySessionStorage) setUpContainer() {
  final auth = FakeAccountAuth();
  final storage = MemorySessionStorage()..token = 't';
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    sessionStorageProvider.overrideWithValue(storage),
    sessionProvider.overrideWith(SignedIn.new),
    browserAuthorizerProvider.overrideWithValue(FakeBrowser()),
  ]);
  addTearDown(container.dispose);
  return (container, auth, storage);
}

Widget app(ProviderContainer container, Widget child) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(theme: buildVixeoTheme(), home: child),
);

void main() {
  testWidgets('changes the sign-in email without asking for a password', (tester) async {
    final (container, auth, _) = setUpContainer();
    await tester.pumpWidget(app(container, const AccountScreen()));

    await tester.tap(find.text('Modifier l’adresse e-mail'));
    await tester.pumpAndSettle();
    expect(find.text('Mot de passe'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nouveau@exemple.fr');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['email nouveau@exemple.fr', 'redeem change-code']);
    expect(container.read(sessionProvider).user?.email, 'nouveau@exemple.fr');
    expect(container.read(sessionProvider).token, 'new-token');
  });

  testWidgets('offers account deletion without asking for a password', (tester) async {
    final (container, _, _) = setUpContainer();
    await tester.pumpWidget(app(container, const AccountScreen()));

    expect(find.text('Supprimer mon compte'), findsOneWidget);
    expect(find.text('Mot de passe'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('exports account data by email', (tester) async {
    final (container, auth, _) = setUpContainer();
    await tester.pumpWidget(app(container, const AccountScreen()));

    await tester.ensureVisible(find.text('Recevoir mes données'));
    await tester.tap(find.text('Recevoir mes données'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['export']);
    expect(find.text('Vos données ont été envoyées à davy@exemple.fr.'), findsOneWidget);
  });
}

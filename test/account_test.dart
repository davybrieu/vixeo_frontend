import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/config.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/account/account_screen.dart';
import 'package:vixeo/features/account/devices_screen.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/login_screen.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/password_reset_screen.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/router.dart';

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false);

class FakeAccountAuth extends AuthRepository {
  FakeAccountAuth() : super(ApiClient(token: () => null, profileId: () => null));

  final calls = <String>[];

  @override
  Future<String> forgotPassword(String email) async {
    calls.add('forgot $email');
    return 'Si un compte utilise cette adresse, un code vient d’y être envoyé.';
  }

  @override
  Future<({String token, User user})> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    calls.add('reset $email $code $password');
    if (code != '123456') {
      throw const ApiException(
        'Ce code est incorrect ou a expiré.',
        status: 422,
        fieldErrors: {
          'code': ['Ce code est incorrect ou a expiré.'],
        },
      );
    }
    return (token: 'new-token', user: davy);
  }

  @override
  Future<List<Device>> devices() async => [
    Device(id: 1, name: 'Vixeo Web', current: true, lastUsedAt: DateTime(2026, 11, 4)),
    Device(id: 2, name: 'Vixeo TV', current: false, lastUsedAt: DateTime(2026, 11, 1)),
  ];

  @override
  Future<void> revokeDevice(int id) async => calls.add('revoke $id');

  @override
  Future<String> exportData() async {
    calls.add('export');
    return 'Vos données ont été envoyées à davy@exemple.fr.';
  }

  @override
  Future<void> deleteAccount(String password) async {
    calls.add('delete $password');
    if (password != 'secret-password') {
      throw const ApiException(
        'Mot de passe incorrect.',
        status: 422,
        fieldErrors: {
          'password': ['Mot de passe incorrect.'],
        },
      );
    }
  }
}

class SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedIn, token: 't', user: davy);
}

class SignedOut extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedOut);
}

(ProviderContainer, FakeAccountAuth, MemorySessionStorage) setUpContainer({SessionController Function()? session}) {
  final auth = FakeAccountAuth();
  final storage = MemorySessionStorage()..token = 't';
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      sessionStorageProvider.overrideWithValue(storage),
      if (session != null) sessionProvider.overrideWith(session),
    ],
  );
  addTearDown(container.dispose);
  return (container, auth, storage);
}

Widget app(ProviderContainer container, Widget child) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(theme: buildVixeoTheme(), home: child),
);

void main() {
  test('reads a device', () {
    final device = Device.fromJson({
      'id': 3,
      'name': 'Vixeo TV',
      'current': false,
      'signed_in_at': '2026-11-01T10:00:00Z',
      'last_used_at': null,
      'expires_at': '2027-04-30T10:00:00Z',
    });
    expect(device.name, 'Vixeo TV');
    expect(device.lastUsedAt, isNull);
    expect(device.expiresAt!.year, 2027);
  });

  test('release builds need the publisher and a support address', () {
    expect(AppConfig.checkLegal(publisher: '', supportEmail: '', release: true), contains('PUBLISHER_NAME'));
    expect(AppConfig.checkLegal(publisher: 'Vixeo SAS', supportEmail: 'aide', release: true), isNotNull);
    expect(AppConfig.checkLegal(publisher: 'Vixeo SAS', supportEmail: 'aide@vixeo.app', release: true), isNull);
    expect(AppConfig.checkLegal(publisher: '', supportEmail: '', release: false), isNull);
  });

  testWidgets('forgotten password: code by e-mail, then a new password signs in', (tester) async {
    final (container, auth, storage) = setUpContainer(session: SignedOut.new);
    await tester.pumpWidget(app(container, const PasswordResetScreen(initialEmail: 'davy@exemple.fr')));

    await tester.tap(find.text('Recevoir un code'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['forgot davy@exemple.fr']);
    expect(find.textContaining('Saisissez le code à 6 chiffres envoyé à davy@exemple.fr'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Code reçu par e-mail'), '000000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nouveau mot de passe'), 'new-secret-password');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirmation du mot de passe'), 'new-secret-password');
    await tester.ensureVisible(find.text('Changer le mot de passe'));
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pumpAndSettle();
    expect(find.text('Ce code est incorrect ou a expiré.'), findsOneWidget);
    expect(container.read(sessionProvider).isSignedIn, isFalse);

    await tester.enterText(find.widgetWithText(TextFormField, 'Code reçu par e-mail'), '123456');
    await tester.ensureVisible(find.text('Changer le mot de passe'));
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pumpAndSettle();
    expect(auth.calls.last, 'reset davy@exemple.fr 123456 new-secret-password');
    expect(container.read(sessionProvider).isSignedIn, isTrue);
    expect(storage.token, 'new-token');
  });

  testWidgets('forgotten password: both new passwords must match', (tester) async {
    final (container, auth, _) = setUpContainer(session: SignedOut.new);
    await tester.pumpWidget(app(container, const PasswordResetScreen(initialEmail: 'davy@exemple.fr')));
    await tester.tap(find.text('Recevoir un code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Code reçu par e-mail'), '123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nouveau mot de passe'), 'new-secret-password');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirmation du mot de passe'), 'other-password');
    await tester.ensureVisible(find.text('Changer le mot de passe'));
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pumpAndSettle();

    expect(find.text('Les deux mots de passe ne sont pas identiques.'), findsOneWidget);
    expect(auth.calls, ['forgot davy@exemple.fr']);
  });

  testWidgets('deleting the account asks the password, then signs out', (tester) async {
    final (container, auth, storage) = setUpContainer(session: SignedIn.new);
    await tester.pumpWidget(app(container, const AccountScreen()));

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.text('Supprimer définitivement'));
    await tester.pumpAndSettle();
    expect(find.text('Mot de passe incorrect.'), findsOneWidget);
    expect(container.read(sessionProvider).isSignedIn, isTrue);

    await tester.enterText(find.byType(TextField).last, 'secret-password');
    await tester.tap(find.text('Supprimer définitivement'));
    await tester.pumpAndSettle();
    expect(auth.calls.last, 'delete secret-password');
    final session = container.read(sessionProvider);
    expect(session.status, SessionStatus.signedOut);
    expect(session.message, contains('supprimés'));
    expect(storage.token, isNull);
  });

  testWidgets('asks for a copy of the data by e-mail', (tester) async {
    final (container, auth, _) = setUpContainer(session: SignedIn.new);
    await tester.pumpWidget(app(container, const AccountScreen()));

    await tester.tap(find.text('Recevoir mes données'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['export']);
    expect(find.text('Vos données ont été envoyées à davy@exemple.fr.'), findsOneWidget);
  });

  testWidgets('lists the devices and signs another one out', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (container, auth, _) = setUpContainer(session: SignedIn.new);
    await tester.pumpWidget(app(container, const DevicesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Cet appareil'), findsOneWidget);
    expect(find.textContaining('Dernière activité le 4 novembre 2026'), findsOneWidget);

    await tester.tap(find.text('Déconnecter').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Déconnecter')));
    await tester.pumpAndSettle();

    expect(auth.calls, ['revoke 2']);
    expect(find.text('« Vixeo TV » a été déconnecté.'), findsOneWidget);
  });

  testWidgets('sign-in pages are open without an account, account pages are not', (tester) async {
    final (container, _, _) = setUpContainer(session: SignedOut.new);
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    router.go('/mot-de-passe-oublie');
    await tester.pumpAndSettle();
    expect(find.byType(PasswordResetScreen), findsOneWidget);

    // Account pages still need a session.
    router.go('/profil/compte');
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

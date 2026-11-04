import 'package:flutter/material.dart';
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
}

void main() {
  late FakeAuthRepository auth;
  late MemorySessionStorage storage;
  late ProviderContainer container;

  setUp(() {
    VxFonts.useGoogleFonts = false;
    auth = FakeAuthRepository();
    storage = MemorySessionStorage();
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth), sessionStorageProvider.overrideWithValue(storage)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildVixeoTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

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

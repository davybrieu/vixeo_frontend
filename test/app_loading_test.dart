import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/app_loading.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/profiles/profiles_screen.dart';
import 'package:vixeo/router.dart';

class Restoring extends SessionController {
  @override
  SessionState build() => const SessionState.restoring();
}

class SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    user: User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false),
  );
}

/// One start-up loading only (developer's request): nothing in the web page before Flutter, then
/// the same logo and spinner on every screen of the start, never two loadings at once.
void main() {
  Widget app(Widget home, List overrides) => ProviderScope(
    overrides: [...overrides],
    child: MaterialApp(theme: buildVixeoTheme(), home: home),
  );

  testWidgets('checking the session: the start-up loading, alone', (tester) async {
    await tester.pumpWidget(app(const SplashScreen(), [sessionProvider.overrideWith(Restoring.new)]));
    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('« Qui regarde ? » while the profiles load: the same loading, without the page around', (tester) async {
    final pending = Completer<List<Profile>>();
    await tester.pumpWidget(
      app(const ProfilesScreen(), [
        sessionProvider.overrideWith(SignedIn.new),
        profilesProvider.overrideWith((ref) => pending.future),
      ]),
    );
    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Se déconnecter'), findsNothing);

    pending.complete(const [Profile(id: 1, name: 'Davy')]);
    await tester.pump();
    expect(find.byType(AppLoading), findsNothing);
    expect(find.text('Qui regarde ?'), findsOneWidget);
  });

  test('the web page has no loading of its own before Flutter', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, isNot(contains('spinner')));
    expect(html, isNot(contains('boot-loader')));
  });
}

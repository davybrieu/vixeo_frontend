import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/profiles/advanced_settings_screen.dart';

/// `GET /me` and the profiles.
class ProfilesAuth extends AuthRepository {
  ProfilesAuth() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<User> me() async => const User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false);

  @override
  Future<List<Profile>> profiles() async => const [Profile(id: 1, name: 'Davy'), Profile(id: 2, name: 'Léa')];
}

Future<SessionState> restored(MemorySessionStorage storage) async {
  final container = ProviderContainer(
    overrides: [
      sessionStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(ProfilesAuth()),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider);
  await container.read(sessionProvider.notifier).restore();
  return container.read(sessionProvider);
}

void main() {
  group('« Mémoriser le dernier profil »', () {
    test('on (default): the last profile opens at launch', () async {
      final state = await restored(MemorySessionStorage()
        ..token = 't'
        ..profileId = 2);
      expect(state.profile?.id, 2);
    });

    test('off: « Qui regarde ? » at launch', () async {
      final state = await restored(MemorySessionStorage()
        ..token = 't'
        ..profileId = 2
        ..rememberProfile = false);
      expect(state.isSignedIn, isTrue);
      expect(state.profile, isNull);
    });
  });

  group('« Avancé » page', () {
    late MemorySessionStorage storage;
    late int emptied;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(520, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      storage = MemorySessionStorage();
      emptied = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStorageProvider.overrideWithValue(storage),
            imageDiskCacheProvider.overrideWithValue(() async => emptied++),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const AdvancedSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('turns « Mémoriser le dernier profil » off and on', (tester) async {
      await pump(tester);
      expect(find.bySemanticsLabel('Mémoriser le dernier profil, activé'), findsOneWidget);

      await tester.tap(find.text('Mémoriser le dernier profil'));
      await tester.pumpAndSettle();
      expect(storage.rememberProfile, isFalse);
      expect(find.text('« Qui regarde ? » s’affichera au lancement'), findsOneWidget);
      expect(find.bySemanticsLabel('Mémoriser le dernier profil, désactivé'), findsOneWidget);

      await tester.tap(find.text('Mémoriser le dernier profil'));
      await tester.pumpAndSettle();
      expect(storage.rememberProfile, isTrue);
    });

    testWidgets('empties the cache', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Vider le cache'));
      await tester.pumpAndSettle();

      expect(emptied, 1);
      expect(find.text('Cache vidé'), findsOneWidget);
    });
  });
}

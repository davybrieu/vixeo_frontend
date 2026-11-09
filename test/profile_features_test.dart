import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/common.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/actions.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/profiles/profile_preferences_screen.dart';
import 'package:vixeo/features/profiles/profile_settings_screen.dart';

/// In-memory library: records favorites / watched like the sync API would.
class FakeLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});

  void _put(MediaItem item, {bool? favorite, bool? watched}) {
    final items = Map.of(state.value!.items);
    final key = 'tmdb|${item.syncId}';
    final old = items[key];
    items[key] = ProfileItem(
      source: 'tmdb',
      itemId: item.syncId,
      type: item.type.name,
      title: item.title,
      isFavorite: favorite ?? old?.isFavorite ?? false,
      isWatched: watched ?? old?.isWatched ?? false,
    );
    state = AsyncData(LibraryState(items));
  }

  @override
  Future<void> setFavorite(MediaItem item, bool value) async => _put(item, favorite: value);

  @override
  Future<void> setWatched(MediaItem item, bool value) async => _put(item, watched: value);
}

/// Signed in with a given profile, no storage, no network.
class FakeSession extends SessionController {
  FakeSession(this.profile);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', profile: profile);
}

/// Saves profile fields without the API.
class SavingAuth extends AuthRepository {
  SavingAuth() : super(ApiClient(token: () => null, profileId: () => null));

  final updates = <Map<String, Object?>>[];

  @override
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    updates.add(fields);
    return Profile(id: profileId, name: 'Davy', avatar: fields['avatar'] as String?);
  }
}

const movie = MediaItem(id: 550, type: MediaType.movie, title: 'Nord Sauvage');

Widget app(Widget child, {Profile profile = const Profile(id: 1, name: 'Davy')}) => ProviderScope(
  // A new scope per profile (overrides are read once per scope).
  key: ValueKey(profile.id),
  overrides: [libraryProvider.overrideWith(FakeLibrary.new), sessionProvider.overrideWith(() => FakeSession(profile))],
  child: MaterialApp(
    theme: buildVixeoTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('one icon-only button adds to and removes from the list, with an alert', (tester) async {
    await tester.pumpWidget(app(const FavoriteButton(item: movie)));
    await tester.pumpAndSettle();

    // No visible text, only the icon (the label is for screen readers).
    expect(find.descendant(of: find.byType(VxIconAction), matching: find.byType(Text)), findsNothing);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Ajouter à ma liste'), findsOneWidget);

    await tester.tap(find.byType(VxIconAction));
    await tester.pumpAndSettle();
    expect(find.text('Ajouté à votre liste'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_added_rounded), findsWidgets);

    await tester.tap(find.byType(VxIconAction));
    await tester.pumpAndSettle();
    expect(find.text('Supprimé de votre liste'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
  });

  testWidgets('the same button marks a movie as watched or not watched', (tester) async {
    await tester.pumpWidget(app(const WatchedButton(item: movie)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VxIconAction));
    await tester.pumpAndSettle();
    expect(find.text('Marqué comme vu'), findsOneWidget);

    await tester.tap(find.byType(VxIconAction));
    await tester.pumpAndSettle();
    expect(find.text('Marqué comme non vu'), findsOneWidget);
  });

  testWidgets('rows use vertical posters by default and horizontal images when the profile asks', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final row = PosterRow(title: 'Films tendance', items: const [movie]);

    await tester.pumpWidget(app(row));
    await tester.pumpAndSettle();
    var size = tester.getSize(find.byType(PosterCard));
    expect(size.height / size.width, closeTo(1.5, 0.01));

    await tester.pumpWidget(
      app(
        row,
        profile: const Profile(id: 2, name: 'Léa', posterFormat: PosterFormat.landscape),
      ),
    );
    await tester.pumpAndSettle();
    size = tester.getSize(find.byType(PosterCard));
    expect(size.height / size.width, closeTo(9 / 16, 0.01));
    // A title without any image shows its name instead.
    expect(find.text('Nord Sauvage'), findsOneWidget);
  });

  testWidgets('poster cards show the image without the name, in both formats', (tester) async {
    const withImages = MediaItem(
      id: 551,
      type: MediaType.movie,
      title: 'Nord Sauvage',
      posterUrl: 'https://image.tmdb.org/t/p/w342/p.jpg',
      backdropUrl: 'https://image.tmdb.org/t/p/w780/b.jpg',
    );
    for (final format in PosterFormat.values) {
      await tester.pumpWidget(app(PosterCard(item: withImages, width: 200, format: format)));
      await tester.pump();
      expect(find.text('Nord Sauvage'), findsNothing, reason: format.name);
      expect(find.bySemanticsLabel(RegExp('^Nord Sauvage, film')), findsOneWidget, reason: format.name);
    }
  });

  test('reads the poster format of a profile', () {
    expect(Profile.fromJson({'id': 1, 'name': 'A'}).posterFormat, PosterFormat.portrait);
    expect(Profile.fromJson({'id': 1, 'name': 'A', 'poster_format': 'landscape'}).posterFormat, PosterFormat.landscape);
  });

  test('reads avatars grouped by license', () {
    final license = AvatarLicense.fromJson({
      'id': 'vixeo-arcade',
      'name': 'Vixeo Arcade',
      'avatars': [
        {
          'id': 'arcade-cat',
          'name': 'Chat',
          'background': '#2A2112',
          'image_url': null,
          'pixels': ['.K', 'KK'],
          'palette': {'K': '#F59E0B', 'X': 'not-a-color'},
        },
      ],
    });

    final cat = license.avatars.single;
    expect(license.name, 'Vixeo Arcade');
    expect(cat.background, const Color(0xFF2A2112));
    expect(cat.palette, {'K': const Color(0xFFF59E0B)});
    expect(cat.pixels, ['.K', 'KK']);
    expect(parseHexColor('#12'), isNull);
  });

  testWidgets('shows the initial until the avatar catalog knows the avatar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [avatarCatalogProvider.overrideWith((ref) async => const <AvatarLicense>[])],
        child: const MaterialApp(
          home: AvatarTile(avatarId: 'unknown', initial: 'D', size: 80),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('the avatar picker only offers avatars: no "initial" choice at the top', (tester) async {
    const licenses = [
      AvatarLicense(
        id: 'vixeo-arcade',
        name: 'Vixeo Arcade',
        avatars: [
          AvatarDef(id: 'arcade-cat', name: 'Chat', background: Color(0xFF2A2112)),
          AvatarDef(id: 'arcade-fox', name: 'Renard', background: Color(0xFF2A2112)),
        ],
      ),
    ];
    Future<void> open(Profile profile) async {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(profile.avatar),
          overrides: [
            avatarCatalogProvider.overrideWith((ref) async => licenses),
            sessionProvider.overrideWith(() => FakeSession(profile)),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const AvatarPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    // A profile without an avatar yet (made before avatars were given): the first one has the focus.
    await open(const Profile(id: 1, name: 'Davy'));
    expect(find.text('Initiale'), findsNothing);
    expect(find.text('D'), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Renard'), findsOneWidget);
    expect(focused(), contains('Chat'));

    // With an avatar: that one has the focus.
    await open(const Profile(id: 1, name: 'Davy', avatar: 'arcade-fox'));
    expect(focused(), contains('Renard'));
  });

  testWidgets('choosing an avatar saves it and stays on the page', (tester) async {
    final auth = SavingAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          avatarCatalogProvider.overrideWith(
            (ref) async => const [
              AvatarLicense(
                id: 'vixeo-arcade',
                name: 'Vixeo Arcade',
                avatars: [
                  AvatarDef(id: 'arcade-cat', name: 'Chat', background: Color(0xFF2A2112)),
                  AvatarDef(id: 'arcade-fox', name: 'Renard', background: Color(0xFF2A2112)),
                ],
              ),
            ],
          ),
          authRepositoryProvider.overrideWithValue(auth),
          sessionProvider.overrideWith(() => FakeSession(const Profile(id: 1, name: 'Davy', avatar: 'arcade-cat'))),
        ],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AvatarPickerScreen())),
                child: const Text('Paramètres'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Renard'));
    await tester.pumpAndSettle();
    expect(auth.updates, [
      {'avatar': 'arcade-fox'},
    ]);
    expect(find.text('Avatar mis à jour'), findsOneWidget);
    // Still on the page, the new one selected.
    expect(find.text('Choisir un avatar'), findsOneWidget);
    expect(find.bySemanticsLabel('Renard, sélectionné'), findsOneWidget);
    expect(find.bySemanticsLabel('Chat'), findsOneWidget);
  });

  testWidgets('Paramètres: the same gaps between every section', (tester) async {
    // A phone (under 600 px), wide enough for the test font (wider than Inter).
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(() => FakeSession(const Profile(id: 1, name: 'Davy')))],
        child: MaterialApp(theme: buildVixeoTheme(), home: const ProfilePreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    Rect row(String label) =>
        tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(VxFocusable)).first);
    Rect heading(String title) => tester.getRect(find.text(title));
    // Each section: its title, its first row and its last row.
    final sections = [
      (heading('Apparence'), row('Format des affiches'), row('Format des affiches')),
      (heading('No spoil'), row('Activer No spoil'), row('Activer No spoil')),
      (heading('Langues'), row('Langue audio préférée'), row('Sous-titres')),
      (heading('Passer automatiquement'), row('Générique de début'), row('Aperçu de la suite')),
    ];
    final underTitles = {for (final (title, first, _) in sections) first.top - title.bottom};
    final betweenSections = {for (var i = 1; i < sections.length; i++) sections[i].$1.top - sections[i - 1].$3.bottom};
    expect(underTitles, hasLength(1));
    expect(betweenSections, hasLength(1));
    expect(betweenSections.single, 24);
  });
}

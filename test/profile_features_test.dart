import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/common.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/actions.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/profiles/avatars.dart';

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
  setUp(() => VxFonts.useGoogleFonts = false);

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
    // Horizontal images carry the title.
    expect(find.text('Nord Sauvage'), findsOneWidget);
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/features.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/common.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/actions.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/profiles/profile_preferences_screen.dart';
import 'package:vixeo/features/ratings/ratings.dart';
import 'package:vixeo/features/shell/app_shell.dart';

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

Widget app(
  Widget child, {
  Profile profile = const Profile(id: 1, name: 'Davy'),
  bool liveTv = false,
  List<Override> overrides = const [],
}) => ProviderScope(
  // A new scope per profile (overrides are read once per scope).
  key: ValueKey((profile.id, profile.ratingSource, liveTv)),
  overrides: [
    libraryProvider.overrideWith(FakeLibrary.new),
    sessionProvider.overrideWith(() => FakeSession(profile)),
    liveTvProvider.overrideWithValue(liveTv),
    ...overrides,
  ],
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
    // On a phone the card is its image, then the caption (name, year and rating).
    double imageRatio() {
      final size = tester.getSize(find.byType(PosterCard));
      final caption = PosterCard.captionHeightOf(tester.element(find.byType(PosterCard)));
      return (size.height - caption) / size.width;
    }

    expect(imageRatio(), closeTo(1.5, 0.01));

    await tester.pumpWidget(
      app(
        row,
        profile: const Profile(id: 2, name: 'Léa', posterFormat: PosterFormat.landscape),
      ),
    );
    await tester.pumpAndSettle();
    expect(imageRatio(), closeTo(9 / 16, 0.01));
    // A title without any image shows its name in the image too (and in the caption).
    expect(find.text('Nord Sauvage'), findsNWidgets(2));
  });

  testWidgets('phone: name, then year (left) and rating (right) under each poster card', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const item = MediaItem(
      id: 551,
      type: MediaType.movie,
      title: 'Nord Sauvage',
      year: 2026,
      voteAverage: 8.4,
      posterUrl: 'https://image.tmdb.org/t/p/w342/p.jpg',
      backdropUrl: 'https://image.tmdb.org/t/p/w780/b.jpg',
    );
    // MDBList has nothing for this title: TMDb's rating, with its logo (also when the profile chose
    // TMDb).
    final noRatings = ratingsLoaderProvider.overrideWithValue(
      RatingsLoader(
        fetch: (titles) async => (ratings: {for (final t in titles) t: TitleRatings.empty}, available: true),
      ),
    );
    for (final format in PosterFormat.values) {
      await tester.pumpWidget(app(PosterCard(item: item, width: 116, format: format), overrides: [noRatings]));
      // The ratings are asked after the frame, then shown.
      await tester.pump();
      await tester.pump();
      final name = tester.widget<Text>(find.text('Nord Sauvage'));
      expect(name.maxLines, 1, reason: format.name);
      // Under the name, on one line: the year on the left, the rating and TMDb's logo on the right.
      final nameY = tester.getCenter(find.text('Nord Sauvage')).dy;
      final year = tester.getCenter(find.text('2026'));
      final rating = tester.getCenter(find.byType(TmdbRating));
      expect(year.dy, greaterThan(nameY), reason: format.name);
      expect(rating.dy, closeTo(year.dy, 2), reason: format.name);
      expect(rating.dx, greaterThan(year.dx), reason: format.name);
      expect(find.descendant(of: find.byType(TmdbRating), matching: find.byType(TmdbLogo)), findsOneWidget);
      // The card is exactly as high as its image and caption: rows and grids rely on it.
      final context = tester.element(find.byType(PosterCard));
      expect(
        tester.getSize(find.byType(PosterCard)).height,
        closeTo(PosterCard.heightFor(116, format) + PosterCard.captionHeightOf(context), 0.01),
        reason: format.name,
      );
    }
  });

  testWidgets('tablet and TV: poster cards show the image without the name, in both formats', (tester) async {
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

  testWidgets('the side rail fits a low screen (smaller icons), then scrolls', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    const labels = ['Accueil', 'Chaînes TV', 'Recherche', 'Profil', 'Paramètres'];

    // A phone held sideways: everything is visible, with smaller icons than the usual 52.
    tester.view.physicalSize = const Size(700, 340);
    await tester.pumpWidget(app(const AppShell(location: '/recherche', child: SizedBox()), liveTv: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final label in labels) {
      final item = tester.getRect(find.byTooltip(label));
      expect(item.bottom, lessThanOrEqualTo(340), reason: label);
      expect(item.height, lessThan(52), reason: label);
    }

    // Lower still: the icons keep a pressable size and the rail scrolls.
    tester.view.physicalSize = const Size(700, 220);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byTooltip('Recherche')).height, 40);
    final rail = find.ancestor(of: find.byTooltip('Recherche'), matching: find.byType(Scrollable)).first;
    expect(tester.state<ScrollableState>(rail).position.maxScrollExtent, greaterThan(0));
    await tester.scrollUntilVisible(find.byTooltip('Chaînes TV'), 60, scrollable: rail);
    expect(tester.getRect(find.byTooltip('Chaînes TV')).bottom, lessThanOrEqualTo(220));
  });

  testWidgets('live TV hidden (for now): no « Chaînes TV » in the rail', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(app(const AppShell(location: '/recherche', child: SizedBox())));
    await tester.pump();

    expect(find.byTooltip('Chaînes TV'), findsNothing);
    for (final label in ['Accueil', 'Recherche', 'Profil', 'Paramètres']) {
      expect(find.byTooltip(label), findsOneWidget, reason: label);
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
      (heading('Apparence'), row('Format des affiches'), row('Source des notes')),
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

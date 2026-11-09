import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/hero.dart';
import 'package:vixeo/features/catalog/home_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/library.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

const homeLogo = 'https://image.tmdb.org/t/p/w500/orbite.png';
const pageLogo = 'https://image.tmdb.org/t/p/w500/phare.png';

final home = Home(
  featured: const [
    MediaItem(
      id: 2,
      type: MediaType.movie,
      title: 'Orbite 9',
      logoUrl: homeLogo,
      logoAspectRatio: 3,
      posterPath: '/orbite.jpg',
      posterUrl: 'https://image.tmdb.org/t/p/w342/orbite.jpg',
      backdropPath: '/orbite-wide.jpg',
      backdropUrl: 'https://image.tmdb.org/t/p/w780/orbite-wide.jpg',
      textlessPosterPath: '/orbite-clean.jpg',
      textlessPosterUrl: 'https://image.tmdb.org/t/p/w500/orbite-clean.jpg',
    ),
    MediaItem(id: 3, type: MediaType.movie, title: 'Le Phare'),
  ],
  sections: [
    Section(
      key: 'movie_trending',
      title: 'Films tendance',
      type: MediaType.movie,
      list: 'trending',
      items: const [
        // The home gives the logo of the first title, not of the second.
        MediaItem(id: 2, type: MediaType.movie, title: 'Orbite 9', logoUrl: homeLogo, logoAspectRatio: 3),
        MediaItem(id: 3, type: MediaType.movie, title: 'Le Phare'),
      ],
    ),
  ],
);

Future<void> pumpHome(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeProvider.overrideWith((ref, type) async => home),
        libraryProvider.overrideWith(EmptyLibrary.new),
        // Its title page has a logo for "Le Phare".
        titleProvider.overrideWith(
          (ref, key) async => TitleDetails(
            id: key.$2,
            type: key.$1,
            title: key.$2 == 3 ? 'Le Phare' : 'Orbite 9',
            logoUrl: key.$2 == 3 ? pageLogo : null,
            logoAspectRatio: 2,
          ),
        ),
      ],
      child: MaterialApp(
        shortcuts: remoteShortcuts,
        actions: remoteActions,
        theme: buildVixeoTheme(),
        home: const Scaffold(body: HomeScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder logo(String url) => find.byWidgetPredicate((w) => w is CachedNetworkImage && w.imageUrl == url);

void main() {
  testWidgets('large screen: the hero shows the logo of the title, else its name', (tester) async {
    await pumpHome(tester, const Size(1920, 1080));

    // The home gives the logo of "Orbite 9": shown at once, the name stays for screen readers.
    expect(logo(homeLogo), findsOneWidget);
    expect(find.bySemanticsLabel('Orbite 9'), findsWidgets);

    // "Le Phare": its name first, then the logo of its title page once the selection rests.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    // After the crossfade (the selection reaches the hero on the next frame).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(logo(homeLogo), findsNothing);
    // The name (in the hero, and on its card, which has no image here).
    expect(find.text('Le Phare'), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(logo(pageLogo), findsOneWidget);
  });

  testWidgets('a full hero fits its room, on the home and on the search page', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overview = 'Un très long résumé qui remplit largement les deux lignes prévues pour lui. ' * 6;
    final item = MediaItem(
      id: 2,
      type: MediaType.movie,
      title: 'Orbite 9',
      overview: overview,
      year: 2026,
      voteAverage: 8.1,
      logoUrl: homeLogo,
      logoAspectRatio: 1.2,
    );
    for (final (compact, height) in [(false, 500.0), (true, 350.0)]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            titleProvider.overrideWith(
              (ref, key) async => TitleDetails(
                id: 2,
                type: MediaType.movie,
                title: 'Orbite 9',
                overview: overview,
                year: 2026,
                runtime: 152,
                ageRating: 16,
                genres: const [Genre(18, 'Drame'), Genre(12, 'Aventure'), Genre(878, 'Science-Fiction')],
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: height,
                  child: HeroText(item: item, compact: compact),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      // An overflow would fail the test; the details are there.
      expect(find.text('Drame · Aventure · Science-Fiction'), findsOneWidget);
    }
  });

  testWidgets('phone: the carousel cards show the logo, else the name', (tester) async {
    // A large phone: the test font draws every letter as a square, wider than Sora / Inter.
    await pumpHome(tester, const Size(430, 932));

    expect(logo(homeLogo), findsOneWidget);
    // Full-width card: the backdrop under the logo.
    expect(logo('https://image.tmdb.org/t/p/w1280/orbite-wide.jpg'), findsOneWidget);
    // No logo given by the home for "Le Phare" (next card): its name.
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Le Phare'), findsWidgets);
  });
}

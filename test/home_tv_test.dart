import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/home_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/library.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

/// Title pages of the hero, without network.
TitleDetails details((MediaType, int) key) => TitleDetails(
  id: key.$2,
  type: key.$1,
  title: 'Titre ${key.$2}',
  overview: 'Résumé complet du titre ${key.$2}',
  year: 2024,
  runtime: 126,
  ageRating: 12,
  genres: const [Genre(18, 'Drame'), Genre(12, 'Aventure')],
);

final home = Home(
  featured: [movie(1, 'Nord Sauvage')],
  sections: [
    Section(
      key: 'movie_trending',
      title: 'Films tendance',
      type: MediaType.movie,
      list: 'trending',
      items: [movie(2, 'Orbite 9'), movie(3, 'Le Phare')],
    ),
  ],
);

Future<void> pumpHome(WidgetTester tester, {LibraryController Function() library = EmptyLibrary.new}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeProvider.overrideWith((ref, type) async => home),
        libraryProvider.overrideWith(library),
        titleProvider.overrideWith((ref, key) async => details(key)),
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

MediaItem movie(int id, String title) =>
    MediaItem(id: id, type: MediaType.movie, title: title, overview: 'Résumé de $title');

String? focusedLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<VxFocusable>()?.semanticLabel;
}

void main() {
  testWidgets('TV home: the remote moves from the hero into the rows, and the hero follows the focus', (tester) async {
    await pumpHome(tester);

    // Nothing to resume: the hero button has the focus on arrival.
    expect(focusedLabel(), 'Plus d’infos');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('Orbite 9'));
    // The info panel shows the focused title (with its title page, once loaded).
    expect(find.text('Résumé complet du titre 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('Le Phare'));
    expect(find.text('Le Phare'), findsWidgets);
  });

  testWidgets('the hero shows the title page details once the selection rests', (tester) async {
    await pumpHome(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // At once: what the list gives.
    expect(find.text('Résumé de Orbite 9'), findsOneWidget);
    expect(find.text('Drame · Aventure'), findsNothing);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Drame · Aventure'), findsOneWidget);
    expect(find.text('2 h 06'), findsOneWidget);
    expect(find.text('12+'), findsOneWidget);
    expect(find.text('Résumé complet du titre 2'), findsOneWidget);
  });

  testWidgets('the hero follows the mouse too', (tester) async {
    await pumpHome(tester);
    expect(find.text('Résumé de Nord Sauvage'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final poster = find.bySemanticsLabel(RegExp('^Le Phare'));
    await mouse.moveTo(tester.getCenter(poster.first));
    // Not before the pointer rests on the card.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Résumé de Le Phare'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('Résumé de Le Phare'), findsOneWidget);
  });

  testWidgets('a "Continuer à regarder" card puts its title in the hero', (tester) async {
    await pumpHome(tester, library: ResumeLibrary.new);

    // The first resume card has the focus on arrival: its title is in the hero.
    expect(focusedLabel(), startsWith('Les Veilleurs'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Les Veilleurs'), findsWidgets);
    expect(find.text('Résumé complet du titre 7'), findsOneWidget);
  });
}

class ResumeLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => LibraryState({
    'tmdb|tv:7': ProfileItem(
      source: 'tmdb',
      itemId: 'tv:7',
      type: 'tv',
      title: 'Les Veilleurs',
      positionMs: 600000,
      durationMs: 3000000,
      progress: 0.2,
      lastEngagedAt: DateTime(2026, 11, 4),
    ),
  });
}

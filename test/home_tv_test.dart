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

MediaItem movie(int id, String title) =>
    MediaItem(id: id, type: MediaType.movie, title: title, overview: 'Résumé de $title');

String? focusedLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<VxFocusable>()?.semanticLabel;
}

void main() {
  setUp(() => VxFonts.useGoogleFonts = false);

  testWidgets('TV home: the remote moves from the hero into the rows, and the hero follows the focus', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeProvider.overrideWith((ref, type) async => home),
          libraryProvider.overrideWith(EmptyLibrary.new),
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

    // Nothing to resume: the hero button has the focus on arrival.
    expect(focusedLabel(), 'Plus d’infos');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('Orbite 9'));
    // The info panel shows the focused title.
    expect(find.text('Résumé de Orbite 9'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('Le Phare'));
    expect(find.text('Le Phare'), findsWidgets);
  });
}

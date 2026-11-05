import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/details_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

const cast = [
  Person(id: 1, name: 'Alma Meyer-Lindqvist', role: 'Ingrid'),
  Person(id: 2, name: 'Théo Rivière', role: 'Karl'),
];

Future<void> pumpDetails(WidgetTester tester, TitleDetails title, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        titleProvider.overrideWith((ref, key) async => title),
        libraryProvider.overrideWith(EmptyLibrary.new),
      ],
      child: MaterialApp(
        theme: buildVixeoTheme(),
        home: DetailsScreen(type: title.type, id: title.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The page itself (not a horizontal row).
final pageScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// Names of the person cards, left to right.
List<String> cardNames(WidgetTester tester) =>
    tester.widgetList<PersonCard>(find.byType(PersonCard)).map((c) => '${c.person.name} (${c.role})').toList();

void main() {
  testWidgets('movie: "Créateur et distribution", the director first, then the cast', (tester) async {
    await pumpDetails(
      tester,
      const TitleDetails(
        id: 550,
        type: MediaType.movie,
        title: 'Nord Sauvage',
        cast: cast,
        crew: [Person(id: 9, name: 'Ines Dahl')],
      ),
    );

    await tester.scrollUntilVisible(find.text('Créateur et distribution'), 200, scrollable: pageScroll);
    await tester.pumpAndSettle();
    expect(find.text('Distribution'), findsNothing);
    expect(cardNames(tester), ['Ines Dahl (Réalisation)', 'Alma Meyer-Lindqvist (Ingrid)', 'Théo Rivière (Karl)']);
    expect(find.bySemanticsLabel('Ines Dahl, Réalisation'), findsOneWidget);
    // Only in the row: no "Réalisation : …" line under the overview any more.
    expect(find.textContaining('Réalisation :'), findsNothing);

    // A long name gets two lines on a wider card, instead of being cut after a few letters.
    final name = tester.widget<Text>(find.text('Alma Meyer-Lindqvist'));
    expect(name.maxLines, 2);
    expect(tester.getSize(find.byType(PersonCard).first).width, greaterThanOrEqualTo(100));
  });

  testWidgets('TV show: the creators are marked "Création"', (tester) async {
    await pumpDetails(
      tester,
      const TitleDetails(
        id: 7,
        type: MediaType.tv,
        title: 'Les Veilleurs',
        overview: 'Résumé des Veilleurs',
        cast: cast,
        crew: [Person(id: 9, name: 'Ines Dahl')],
      ),
      size: const Size(1920, 1080),
    );

    await tester.scrollUntilVisible(find.text('Créateur et distribution'), 300, scrollable: pageScroll);
    await tester.pumpAndSettle();
    expect(cardNames(tester).first, 'Ines Dahl (Création)');
    // Title, overview and the sections below start at the same left edge.
    final left = tester.getTopLeft(find.text('Créateur et distribution')).dx;
    expect(tester.getTopLeft(find.text('Les Veilleurs').first).dx, left);
    expect(tester.getTopLeft(find.text('Résumé des Veilleurs')).dx, left);

    // Large screen: no "Avec … · Création : …" line under the overview.
    expect(find.textContaining('Avec '), findsNothing);
    expect(find.textContaining('Création :'), findsNothing);
  });

  testWidgets('no director nor creator: "Distribution" only', (tester) async {
    await pumpDetails(tester, const TitleDetails(id: 3, type: MediaType.movie, title: 'Le Phare', cast: cast));

    await tester.scrollUntilVisible(find.text('Distribution'), 200, scrollable: pageScroll);
    expect(find.text('Créateur et distribution'), findsNothing);
    expect(cardNames(tester).first, 'Alma Meyer-Lindqvist (Ingrid)');
  });
}

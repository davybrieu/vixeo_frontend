import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/tv/channel_row.dart';
import 'package:vixeo/features/tv/channel_screen.dart';
import 'package:vixeo/features/tv/models.dart';
import 'package:vixeo/features/tv/tv_repository.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

const tf1 = TvChannel(id: 'tf1', name: 'TF1', categoryId: 'Généralistes', logo: 'https://img.test/tf1.png');

TvProgramme programme(String title, double fromHours, double toHours, {String? description}) {
  final now = DateTime.now();
  return TvProgramme(
    title: title,
    start: now.add(Duration(minutes: (fromHours * 60).round())),
    end: now.add(Duration(minutes: (toHours * 60).round())),
    category: 'Information',
    description: description,
  );
}

Future<void> pumpChannel(WidgetTester tester, TvGuide guide, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tvChannelProvider.overrideWith((ref, id) async => tf1),
        tvGuideProvider.overrideWith((ref, id) async => guide),
        tvCategoriesProvider.overrideWith((ref) async => const []),
        libraryProvider.overrideWith(EmptyLibrary.new),
      ],
      child: MaterialApp(
        theme: buildVixeoTheme(),
        home: const ChannelScreen(id: 'tf1', initial: tf1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The page of a live channel (developer's request): opened from every channel tile, like a title
/// page, with « Regarder » and the programme guide (EPG).
void main() {
  test('reads a programme of the guide, in local time', () {
    final guide = TvGuide.fromJson({
      'data': [
        {
          'title': 'Le journal',
          'subtitle': '',
          'description': 'Les infos.',
          'category': 'Information',
          'image': 'https://img.test/jt.jpg',
          'start': '2026-11-10T19:00:00Z',
          'end': '2026-11-10T19:45:00Z',
        },
      ],
      'available': true,
    });
    final p = guide.programmes.single;
    expect(guide.available, isTrue);
    expect(p.subtitle, isNull);
    expect(p.start, DateTime.utc(2026, 11, 10, 19).toLocal());
    expect(p.isOnAt(DateTime.utc(2026, 11, 10, 19, 30).toLocal()), isTrue);
    expect(p.progressAt(DateTime.utc(2026, 11, 10, 19, 15).toLocal()), closeTo(1 / 3, 0.01));
    expect(TvGuide.fromJson({'data': [], 'available': false}).available, isFalse);
  });

  test('writes the hour, with the day when it is not today', () {
    final now = DateTime(2026, 11, 10, 20);
    expect(programmeTime(DateTime(2026, 11, 10, 20, 5), now), '20:05');
    expect(programmeTime(DateTime(2026, 11, 11, 8, 30), now), 'Demain 08:30');
    expect(programmeTime(DateTime(2026, 11, 13, 8, 30), now), 'ven. 08:30');
  });

  testWidgets('shows the channel, « Regarder », what is on now and the next programmes', (tester) async {
    await pumpChannel(
      tester,
      TvGuide(
        available: true,
        programmes: [
          programme('Fini', -2, -1),
          programme('Le journal', -0.5, 0.5, description: 'Les infos du jour.'),
          programme('Le film du soir', 0.5, 2.5),
        ],
      ),
    );
    expect(find.text('TF1'), findsOneWidget);
    expect(find.text('Généralistes'), findsOneWidget);
    expect(find.text('Regarder'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajouter aux favoris'), findsNothing);
    expect(find.text('En ce moment'), findsOneWidget);
    expect(find.text('Les infos du jour.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // A programme already over is not listed.
    expect(find.text('Fini'), findsNothing);

    await tester.scrollUntilVisible(find.text('Le film du soir'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('En cours'), findsOneWidget);

    // A programme opens its whole description.
    await tester.tap(find.text('Le film du soir'));
    await tester.pumpAndSettle();
    expect(find.text('Fermer'), findsOneWidget);
  });

  testWidgets('says when there is no guide', (tester) async {
    await pumpChannel(tester, const TvGuide(available: false, programmes: []));
    expect(find.text('Le programme n’est pas disponible pour le moment.'), findsOneWidget);
    expect(find.text('En ce moment'), findsNothing);
    expect(find.text('Regarder'), findsOneWidget);
  });

  testWidgets('a channel tile opens the channel page', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: ChannelRow(channels: [tf1])),
        ),
        GoRoute(
          path: '/chaine/:id',
          builder: (_, state) => Scaffold(body: Text('page ${state.pathParameters['id']} ${state.extra is TvChannel}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith(EmptyLibrary.new)],
        child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TF1'));
    await tester.pumpAndSettle();
    expect(find.text('page tf1 true'), findsOneWidget);
  });
}

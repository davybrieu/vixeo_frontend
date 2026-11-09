import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/design.dart';
import 'package:vixeo/core/device/layout.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/card.dart';
import 'package:vixeo/core/widgets/common.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/core/widgets/page_header.dart';
import 'package:vixeo/features/account/devices_screen.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/library/my_list_screen.dart';
import 'package:vixeo/features/profiles/profile_preferences_screen.dart';
import 'package:vixeo/features/profiles/profile_settings_screen.dart';
import 'package:vixeo/features/search/filter_bar.dart';
import 'package:vixeo/features/search/search_screen.dart';
import 'package:vixeo/features/tmdb/reviews_screen.dart';
import 'package:vixeo/features/tmdb/tmdb.dart';

// The design charter (docs/charte-graphique.md) applied: the main pages share their header.

class Favorites extends LibraryController {
  @override
  Future<LibraryState> build() async => LibraryState({
    for (final (i, id) in [1, 2].indexed)
      'tmdb|movie:$id': ProfileItem(
        source: 'tmdb',
        itemId: 'movie:$id',
        type: 'movie',
        title: 'Film $id',
        isFavorite: true,
        favoritedAt: DateTime(2026, 11, 1 + i),
      ),
  });
}

class Linked extends TmdbAccountController {
  @override
  Future<TmdbAccount> build() async => const TmdbAccount(linked: true, username: 'davy');
}

class NoReviews extends Reviews {
  @override
  Future<List<RatedItem>> build() async => const [];
}

/// Signed in with a profile, no storage, no network.
class WithProfile extends SessionController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    profile: Profile(id: 1, name: 'Davy'),
  );
}

/// Title pages asked one by one (there should be none), and batches of titles.
final titleRequests = <(MediaType, int)>[];
final batches = <String>[];

Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  titleRequests.clear();
  batches.clear();
  await tester.pumpWidget(
    ProviderScope(
      // A new scope per page: the overrides differ from one page to the next.
      key: UniqueKey(),
      overrides: [
        allGenresProvider.overrideWith((ref) async => const {MediaType.movie: <Genre>[], MediaType.tv: <Genre>[]}),
        titlesProvider.overrideWith((ref, q) async => const Paged(items: <MediaItem>[])),
        titleProvider.overrideWith((ref, key) async {
          titleRequests.add(key);
          return TitleDetails(id: key.$2, type: key.$1, title: 'Titre');
        }),
        titlesByIdProvider.overrideWith((ref, ids) async {
          batches.add(ids);
          return {
            for (final key in ids.split(','))
              (type: MediaType.movie, id: int.parse(key.split(':').last)): MediaItem(
                id: int.parse(key.split(':').last),
                type: MediaType.movie,
                title: 'Film ${key.split(':').last}',
                logoUrl: 'https://image.tmdb.org/t/p/w500/logo${key.split(':').last}.png',
                logoAspectRatio: 3,
              ),
          };
        }),
        libraryProvider.overrideWith(Favorites.new),
        tmdbAccountProvider.overrideWith(Linked.new),
        reviewsProvider.overrideWith(NoReviews.new),
        ...overrides,
      ],
      child: MaterialApp(
        shortcuts: remoteShortcuts,
        actions: remoteActions,
        theme: buildVixeoTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Where the title, the search field and the filters of a page header are.
List<double> headerLayout(WidgetTester tester, String title) => [
  tester.getTopLeft(find.text(title)).dy,
  tester.getTopLeft(find.byType(VxSearchField)).dy,
  tester.getTopLeft(find.byType(FilterBar)).dy,
  tester.getTopLeft(find.byType(VxSearchField)).dx,
];

void main() {
  testWidgets('Recherche, Ma liste and Mes avis share the same header and spacing', (tester) async {
    await pumpPage(tester, const SearchScreen());
    expect(find.byType(VxPageHeader), findsOneWidget);
    final search = headerLayout(tester, 'Recherche');

    await pumpPage(tester, const MyListScreen());
    expect(find.byType(VxPageHeader), findsOneWidget);
    final myList = headerLayout(tester, 'Ma liste');

    await pumpPage(tester, const ReviewsScreen());
    expect(find.byType(VxPageHeader), findsOneWidget);
    final reviews = headerLayout(tester, 'Mes avis');

    expect(myList, search);
    expect(reviews, search);
  });

  testWidgets('Ma liste asks its titles in one request, never one per card', (tester) async {
    await pumpPage(tester, const MyListScreen());

    expect(batches, ['movie:1,movie:2']);
    expect(titleRequests, isEmpty);
    expect(find.byType(PosterCard), findsNWidgets(2));
  });

  testWidgets('a card and its logo show together, once both are loaded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: ImagesTogether(
                urls: ['https://image.tmdb.org/t/p/w780/b.jpg', 'https://image.tmdb.org/t/p/w300/l.png'],
                placeholder: Text('attente'),
                child: Text('image et logo'),
              ),
            ),
            Expanded(
              child: ImagesTogether(
                urls: ['https://image.tmdb.org/t/p/w342/p.jpg'],
                placeholder: Text('attente seule'),
                child: Text('affiche seule'),
              ),
            ),
          ],
        ),
      ),
    );

    // Two images: nothing until both are there. One image: shown as usual.
    expect(find.text('attente'), findsOneWidget);
    expect(find.text('image et logo'), findsNothing);
    expect(find.text('affiche seule'), findsOneWidget);
  });

  test('card logos are asked at the size of a card', () {
    expect(tmdbImageSize('https://image.tmdb.org/t/p/w500/abc.png', 'w300'), 'https://image.tmdb.org/t/p/w300/abc.png');
    expect(
      tmdbImageSize('https://image.tmdb.org/t/p/original/abc.png', 'w300'),
      'https://image.tmdb.org/t/p/w300/abc.png',
    );
    expect(tmdbImageSize(null, 'w300'), isNull);
    const item = MediaItem(
      id: 1,
      type: MediaType.movie,
      title: 'Dune',
      logoUrl: 'https://image.tmdb.org/t/p/w500/l.png',
    );
    expect(item.cardLogoUrl, 'https://image.tmdb.org/t/p/w300/l.png');
  });

  testWidgets('the gaps of the charter, on a phone and on a TV', (tester) async {
    Future<Layout> layoutAt(double width) async {
      late Layout layout;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: Builder(
            builder: (context) {
              layout = Layout.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return layout;
    }

    final phone = await layoutAt(390);
    expect(
      [phone.sectionGap, phone.titleGap, phone.introGap, phone.listGap, phone.cardGap, phone.gutter],
      [24, 12, 16, 12, 10, 20],
    );
    final tv = await layoutAt(1920);
    expect([tv.sectionGap, tv.titleGap, tv.introGap, tv.listGap, tv.cardGap, tv.gutter], [36, 22, 24, 18, 28, 96]);
  });

  testWidgets('the end of a page stays clear of the tab bar', (tester) async {
    late double bottom;
    await tester.pumpWidget(
      MediaQuery(
        // A phone, with the 66 px of the tab bar in the media padding.
        data: const MediaQueryData(size: Size(390, 844), padding: EdgeInsets.only(bottom: 66)),
        child: Builder(
          builder: (context) {
            bottom = pageBottomPadding(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(bottom, 32 + 66);
  });

  testWidgets('Paramètres starts like the other main pages', (tester) async {
    await pumpPage(tester, const SearchScreen());
    final search = tester.getTopLeft(find.text('Recherche'));

    await pumpPage(tester, const ProfileSettingsScreen(), overrides: [sessionProvider.overrideWith(WithProfile.new)]);
    expect(find.byType(VxPageHeader), findsOneWidget);
    // The page title (the first one: a tile is also called « Paramètres »).
    expect(tester.getTopLeft(find.text('Paramètres').first), search);
  });

  testWidgets('secondary pages: texts on the same edge as the cards', (tester) async {
    // A phone wide enough for the test font (wider than Inter).
    const phone = Size(520, 1200);
    await pumpPage(
      tester,
      const ProfilePreferencesScreen(),
      overrides: [sessionProvider.overrideWith(WithProfile.new)],
      size: phone,
    );
    final intro = tester.getTopLeft(find.textContaining('Personnalisez')).dx;
    expect(tester.getTopLeft(find.text('Apparence')).dx, intro);
    expect(
      tester
          .getTopLeft(find.ancestor(of: find.text('Format des affiches'), matching: find.byType(VxFocusable)).first)
          .dx,
      intro,
    );

    await pumpPage(
      tester,
      const DevicesScreen(),
      overrides: [
        sessionProvider.overrideWith(WithProfile.new),
        devicesProvider.overrideWith((ref) async => const [Device(id: 1, name: 'Vixeo Web', current: true)]),
      ],
      size: phone,
    );
    expect(tester.getTopLeft(find.byType(VxCard)).dx, tester.getTopLeft(find.textContaining('180 jours')).dx);
  });

  testWidgets('the logo is drawn at the size of its word and read « Vixeo »', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: VxLogo(size: 40))));
    expect(find.bySemanticsLabel('Vixeo'), findsOneWidget);
    final size = tester.getSize(find.descendant(of: find.byType(VxLogo), matching: find.byType(CustomPaint)));
    // brand/vixeo-logo.svg is 360 × 80, its word set at 76.1.
    expect(size.width, closeTo(360 * 40 / 76.1, 0.01));
    expect(size.height, closeTo(80 * 40 / 76.1, 0.01));
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/local_store.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/library/my_list_screen.dart';
import 'package:vixeo/features/ratings/rating_view.dart';
import 'package:vixeo/features/ratings/ratings.dart';
import 'package:vixeo/features/search/filter_bar.dart';
import 'package:vixeo/features/social/social_repository.dart';

/// Answers every request with [body] and records the requests.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final Object body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Session extends SessionController {
  _Session(this.profile);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', profile: profile);
}

class _NoLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

/// A loader answering from [ratings] (nothing for the other titles), counting its requests.
RatingsLoader fakeLoader(Map<TitleRef, TitleRatings> ratings, {List<List<TitleRef>>? asked}) => RatingsLoader(
  fetch: (titles) async {
    asked?.add(titles);
    return (ratings: {for (final t in titles) t: ratings[t] ?? TitleRatings.empty}, available: true);
  },
);

const dune = (type: MediaType.movie, id: 438631);
const severance = (type: MediaType.tv, id: 95396);

void main() {
  group('RatingSource', () {
    test('writes each site\'s rating on its scale', () {
      expect(RatingSource.imdb.format(8.8), '8,8');
      expect(RatingSource.tomatoes.format(79), '79 %');
      expect(RatingSource.metacritic.format(67), '67');
      expect(RatingSource.letterboxd.format(4.3), '4,3');
      expect(RatingSource.letterboxd.spoken(4.3), '4,3 sur 5');
      expect(RatingSource.audience.spoken(96), '96 %');
      // The « Note » filter of « Ma liste »: tenths of the scale.
      expect(RatingSource.imdb.threshold(7), '7');
      expect(RatingSource.letterboxd.threshold(7), '3,5');
      expect(RatingSource.trakt.threshold(6), '60 %');
      expect(RatingSource.metacritic.threshold(8), '80');
    });

    test('a profile reads its source, IMDb by default', () {
      final profile = Profile.fromJson({'id': 1, 'name': 'Léa', 'rating_source': 'letterboxd'});
      expect(profile.ratingSource, RatingSource.letterboxd);
      expect(Profile.fromJson({'id': 1, 'name': 'Léa'}).ratingSource, RatingSource.imdb);
      expect(Profile.fromJson({'id': 1, 'name': 'Léa', 'rating_source': 'allocine'}).ratingSource, RatingSource.imdb);
    });
  });

  test('shows the profile\'s site, else IMDb, else TMDb', () {
    const ratings = TitleRatings({RatingSource.imdb: 8.1, RatingSource.tomatoes: 92});
    final tomatoes = ShownRating.pick(RatingSource.tomatoes, ratings, 7.4);
    expect((tomatoes.source, tomatoes.value), (RatingSource.tomatoes, 92));
    // No Letterboxd rating for a TV show: IMDb's.
    final letterboxd = ShownRating.pick(RatingSource.letterboxd, ratings, 7.4);
    expect((letterboxd.source, letterboxd.value), (RatingSource.imdb, 8.1));
    // Nothing from MDBList: the title's TMDb average.
    final none = ShownRating.pick(RatingSource.imdb, TitleRatings.empty, 7.4);
    expect((none.source, none.value), (RatingSource.tmdb, 7.4));
    // TMDb chosen: its average, even with an IMDb rating.
    expect(ShownRating.pick(RatingSource.tmdb, ratings, 7.4).source, RatingSource.tmdb);
    expect(ShownRating.pick(RatingSource.imdb, null, 0).isNone, isTrue);
    expect(tomatoes.fraction, closeTo(0.92, 0.001));
    expect(letterboxd.fraction, closeTo(0.81, 0.001));
  });

  test('reads the API\'s answer, one request for 100 titles', () async {
    final adapter = _Adapter({
      'data': [
        {
          'type': 'movie',
          'id': 438631,
          'imdb': 8.0,
          'tmdb': 7.8,
          'trakt': 82,
          'letterboxd': 3.9,
          'tomatoes': 83,
          'audience': 90,
          'metacritic': 74,
          'mal': null,
        },
        {'type': 'tv', 'id': 95396, 'imdb': null, 'tmdb': null},
      ],
      'available': true,
    });
    final repository = RatingsRepository(
      ApiClient(
        token: () => null,
        profileId: () => null,
        dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
      ),
    );

    final answer = await repository.ratings([dune, severance]);

    expect(adapter.requests.single.path, '/catalog/ratings');
    expect(adapter.requests.single.queryParameters, {'ids': 'movie:438631,tv:95396'});
    expect(answer.available, isTrue);
    expect(answer.ratings[dune]![RatingSource.letterboxd], 3.9);
    expect(answer.ratings[dune]![RatingSource.audience], 90);
    expect(answer.ratings[dune]![RatingSource.mal], isNull);
    // Known by MDBList, no rating: empty (kept, not asked again).
    expect(answer.ratings[severance]!.isEmpty, isTrue);
  });

  group('RatingsLoader', () {
    test('asks the titles of a frame together, 100 per request, each once', () async {
      final asked = <List<TitleRef>>[];
      final titles = [for (var i = 1; i <= 150; i++) (type: MediaType.movie, id: i)];
      final loader = fakeLoader({for (final t in titles) t: const TitleRatings({RatingSource.imdb: 7})}, asked: asked);

      final results = await Future.wait([for (final t in titles) loader.get(t), loader.get(titles.first)]);

      expect(asked.map((request) => request.length), [100, 50]);
      expect(results.every((r) => r[RatingSource.imdb] == 7), isTrue);
      // Known now: no request.
      expect(loader.peek(titles.last)?[RatingSource.imdb], 7);
      await loader.get(titles.last);
      expect(asked, hasLength(2));
    });

    test('without an answer, TMDb meanwhile and asked again 2 minutes later', () async {
      var now = DateTime(2026, 11, 20, 12);
      var calls = 0;
      var fail = true;
      final loader = RatingsLoader(
        now: () => now,
        fetch: (titles) async {
          calls++;
          if (fail) throw Exception('Pas de réseau.');
          return (ratings: {for (final t in titles) t: const TitleRatings({RatingSource.imdb: 8})}, available: true);
        },
      );

      expect((await loader.get(dune)).isEmpty, isTrue);
      fail = false;
      expect((await loader.get(dune)).isEmpty, isTrue);
      expect(calls, 1);

      now = now.add(const Duration(minutes: 3));
      expect((await loader.get(dune))[RatingSource.imdb], 8);
      expect(calls, 2);
    });

    test('a title the API could not ask MDBList for is asked again later', () async {
      var now = DateTime(2026, 11, 20, 12);
      final asked = <List<TitleRef>>[];
      var available = false;
      final loader = RatingsLoader(
        now: () => now,
        fetch: (titles) async {
          asked.add(titles);
          return (
            ratings: {if (available) for (final t in titles) t: const TitleRatings({RatingSource.tomatoes: 95})},
            available: available,
          );
        },
      );

      expect((await loader.get(severance)).isEmpty, isTrue);
      available = true;
      now = now.add(const Duration(minutes: 3));
      expect((await loader.get(severance))[RatingSource.tomatoes], 95);
      expect(asked, hasLength(2));
    });

    test('reads the ratings kept on the device for a day: no request for them', () async {
      final now = DateTime(2026, 11, 20, 12);
      int seconds(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
      final store = MemoryLocalStore();
      store.values[RatingsLoader.storeKey] = jsonEncode({
        'v': 1,
        'sources': ['imdb', 'tmdb', 'a-site-removed-since'],
        'items': {
          'movie:438631': [seconds(const Duration(hours: 2)), 8.0, 7.8, 5],
          // Older than a day: asked again.
          'tv:95396': [seconds(const Duration(hours: 30)), 8.7, null, null],
        },
      });
      final asked = <List<TitleRef>>[];
      final loader = RatingsLoader(
        store: store,
        now: () => now,
        fetch: (titles) async {
          asked.add(titles);
          return (ratings: {for (final t in titles) t: const TitleRatings({RatingSource.imdb: 8.6})}, available: true);
        },
      );
      // The device is read at once, without waiting for a title.
      await Future<void>.delayed(Duration.zero);

      expect((await loader.get(dune)).values, {RatingSource.imdb: 8.0, RatingSource.tmdb: 7.8});
      expect((await loader.get(severance))[RatingSource.imdb], 8.6);
      expect(asked, [
        [severance],
      ]);
    });

    testWidgets('keeps the answers on the device, read at the next launch', (tester) async {
      final store = MemoryLocalStore();
      final first = fakeLoader({dune: const TitleRatings({RatingSource.tomatoes: 79})});
      final saving = RatingsLoader(fetch: first.fetch, store: store);
      addTearDown(saving.dispose);
      unawaited(saving.get(dune));
      await tester.pump();
      // Saved a few seconds after the answers.
      await tester.pump(const Duration(seconds: 6));
      expect(store.values[RatingsLoader.storeKey], contains('movie:438631'));

      final next = RatingsLoader(fetch: (titles) async => throw Exception('not asked'), store: store);
      addTearDown(next.dispose);
      await tester.pump();
      expect(next.peek(dune)?[RatingSource.tomatoes], 79);

      // « Vider le cache »: gone, on the device too.
      next.clear();
      await tester.pump();
      expect(next.peek(dune), isNull);
      expect(store.values, isEmpty);
    });
  });

  group('display', () {
    Widget app(Widget child, {RatingSource source = RatingSource.imdb, RatingsLoader? loader}) => ProviderScope(
      // A new scope per source (overrides are read once per scope).
      key: ValueKey(source),
      overrides: [
        sessionProvider.overrideWith(() => _Session(Profile(id: 1, name: 'Léa', ratingSource: source))),
        libraryProvider.overrideWith(_NoLibrary.new),
        ratingsLoaderProvider.overrideWithValue(loader ?? fakeLoader(const {})),
      ],
      child: MaterialApp(
        theme: buildVixeoTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    );

    testWidgets('a rating with its site: value, tag, read with its scale', (tester) async {
      await tester.pumpWidget(
        app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RatingLabel(source: RatingSource.imdb, value: 8.8),
              RatingLabel(source: RatingSource.tomatoes, value: 79),
              RatingLabel(source: RatingSource.tmdb, value: 7.1),
            ],
          ),
        ),
      );

      expect(find.text('8,8'), findsOneWidget);
      expect(find.text('IMDb'), findsOneWidget);
      expect(find.bySemanticsLabel('Note IMDb : 8,8 sur 10'), findsOneWidget);
      expect(find.text('79 %'), findsOneWidget);
      expect(find.text('RT'), findsOneWidget);
      expect(find.bySemanticsLabel('Note Rotten Tomatoes (critiques) : 79 %'), findsOneWidget);
      // TMDb keeps its logo.
      expect(find.byType(TmdbLogo), findsOneWidget);
    });

    testWidgets('phone card: the profile\'s site under the poster, else IMDb', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const card = MediaItem(id: 438631, type: MediaType.movie, title: 'Dune', year: 2021, voteAverage: 7.8);
      final loader = fakeLoader({dune: const TitleRatings({RatingSource.imdb: 8.0, RatingSource.letterboxd: 3.9})});

      await tester.pumpWidget(
        app(const PosterCard(item: card, width: 116), source: RatingSource.letterboxd, loader: loader),
      );
      // Asked after the frame, then shown.
      await tester.pump();
      await tester.pump();
      expect(find.text('3,9'), findsOneWidget);
      expect(find.text('LB'), findsOneWidget);

      // Rotten Tomatoes chosen, none for this title: IMDb's (known already: at once).
      await tester.pumpWidget(
        app(const PosterCard(item: card, width: 116), source: RatingSource.tomatoes, loader: loader),
      );
      await tester.pump();
      expect(find.text('8,0'), findsOneWidget);
      expect(find.text('IMDb'), findsOneWidget);
      expect(find.byType(TmdbRating), findsNothing);
    });

    testWidgets('« Ma liste » sorts and filters on the profile\'s site, not TMDb', (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const a = MediaItem(id: 1, type: MediaType.movie, title: 'Arrakis', voteAverage: 9);
      const b = MediaItem(id: 2, type: MediaType.movie, title: 'Bene', voteAverage: 5);
      const c = MediaItem(id: 3, type: MediaType.tv, title: 'Caladan', voteAverage: 7);
      final loader = fakeLoader({
        (type: MediaType.movie, id: 1): const TitleRatings({RatingSource.imdb: 6}),
        (type: MediaType.movie, id: 2): const TitleRatings({RatingSource.imdb: 8.5}),
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(() => _Session(const Profile(id: 1, name: 'Léa'))),
            libraryProvider.overrideWith(_NoLibrary.new),
            ratingsLoaderProvider.overrideWithValue(loader),
            allGenresProvider.overrideWith((ref) async => const {MediaType.movie: <Genre>[], MediaType.tv: <Genre>[]}),
            socialTitlesProvider.overrideWith((ref, username) async => const [a, b, c]),
            titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: MyListScreen(username: 'max'))),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> choose(String chip, String option) async {
        final button = find.ancestor(of: find.textContaining(chip), matching: find.byType(FilterChipButton)).first;
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last);
        await tester.pumpAndSettle();
      }

      List<String> order() {
        final names = ['Arrakis', 'Bene', 'Caladan'].where((n) => find.text(n).evaluate().isNotEmpty).toList();
        // The card's place (its name may wrap on the image: not the same height from one to another).
        Offset at(String n) =>
            tester.getTopLeft(find.ancestor(of: find.text(n).first, matching: find.byType(PosterCard)).first);
        int compare(String x, String y) =>
            at(x).dy != at(y).dy ? at(x).dy.compareTo(at(y).dy) : at(x).dx.compareTo(at(y).dx);
        return names..sort(compare);
      }

      // IMDb: Bene (8,5), Caladan (no IMDb rating: TMDb's 7), Arrakis (6), whatever TMDb says.
      await choose('Tri :', 'Mieux notés');
      expect(order(), ['Bene', 'Caladan', 'Arrakis']);

      // « Note » on IMDb's scale.
      await choose('Note', '7 et plus');
      expect(find.text('Note ≥ 7'), findsOneWidget);
      expect(order(), ['Bene', 'Caladan']);
    });
  });
}

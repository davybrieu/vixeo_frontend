import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/addons/scraper_models.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/playback/playback.dart';
import 'package:vixeo/features/playback/player_screen.dart';
import 'package:vixeo/features/profiles/profile_preferences_screen.dart';
import 'package:vixeo/features/search/search_history.dart';

import 'scraper_fakes.dart';

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr');

class WithProfile extends SessionController {
  WithProfile(this.profile);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', user: davy, profile: profile);
}

/// The API's profile update, in memory.
class FakeProfiles extends AuthRepository {
  FakeProfiles() : super(ApiClient(token: () => null));

  final updates = <Map<String, Object?>>[];
  Map<String, dynamic> json = {'id': 2, 'name': 'Léa'};

  @override
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    updates.add(fields);
    json = {...json, ...fields};
    return Profile.fromJson(json);
  }
}

/// The API's recent searches, in memory.
class FakeHistory extends SearchHistoryRepository {
  FakeHistory() : super(ApiClient(token: () => null));

  final calls = <String>[];
  var stored = <RecentSearch>[const RecentSearch(id: 1, query: 'Dune')];
  bool fail = false;
  int _next = 10;

  @override
  Future<List<RecentSearch>> list(int profileId) async => stored;

  @override
  Future<RecentSearch> add(int profileId, String query) async {
    calls.add('add $query');
    if (fail) throw const ApiException('Pas de réseau.');
    return RecentSearch(id: _next++, query: query, searchedAt: DateTime.now());
  }

  @override
  Future<void> remove(int profileId, int id) async => calls.add('remove $id');

  @override
  Future<void> clear(int profileId) async => calls.add('clear');
}

/// Answers every request with [body] (JSON, or text) and records the requests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.body, {this.status = 200});

  final Object body;
  final int status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancel) async {
    requests.add(options);
    final text = body is String ? body as String : jsonEncode(body);
    return ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: [body is String ? 'text/vtt; charset=utf-8' : 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PlaybackRepository repository(FakeAdapter adapter) => PlaybackRepository(
  ApiClient(
    token: () => 't',
    dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
  ),
);

/// Answers each request with the response whose path matches, so one adapter can serve
/// the provider list and several per-provider calls.
class RoutingAdapter implements HttpClientAdapter {
  RoutingAdapter(this.routes);

  final List<(String, Object, int)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancel) async {
    requests.add(options);
    final match = routes.firstWhere(
      (r) => options.path.contains(r.$1),
      orElse: () => ('', {'message': 'not found'}, 404),
    );
    return ResponseBody.fromString(
      jsonEncode(match.$2),
      match.$3,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient routingClient(RoutingAdapter adapter) => ApiClient(
  token: () => 't',
  dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
);

/// Scrolls to a row of the settings page, then taps it.
Future<void> tapRow(WidgetTester tester, String label) async {
  final row = find.bySemanticsLabel(label).first;
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  group('playback settings', () {
    Future<FakeProfiles> pumpSettings(WidgetTester tester) async {
      final auth = FakeProfiles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            sessionProvider.overrideWith(() => WithProfile(const Profile(id: 2, name: 'Léa'))),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const ProfilePreferencesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('starts with the original version, no subtitles, nothing skipped', (tester) async {
      await pumpSettings(tester);

      expect(find.bySemanticsLabel('Langue audio préférée : Version originale'), findsOneWidget);
      expect(find.bySemanticsLabel('Sous-titres : Désactivés'), findsOneWidget);
      expect(find.bySemanticsLabel('Générique de début, bouton Passer'), findsOneWidget);
      expect(find.bySemanticsLabel('Générique de fin, bouton Passer'), findsOneWidget);
    });

    testWidgets('turns automatic skipping on, for this profile on every device', (tester) async {
      final auth = await pumpSettings(tester);

      await tapRow(tester, 'Générique de fin, bouton Passer');

      expect(auth.updates, [
        {'skip_credits': true},
      ]);
      expect(find.bySemanticsLabel('Générique de fin, passé automatiquement'), findsOneWidget);
      expect(find.text('Générique de fin : passé automatiquement'), findsOneWidget);
    });

    testWidgets('picks the subtitle and audio languages', (tester) async {
      final auth = await pumpSettings(tester);

      await tapRow(tester, 'Sous-titres : Désactivés');
      await tester.tap(find.text('Portugais (Brésil)').last);
      await tester.pumpAndSettle();
      expect(auth.updates.last, {'subtitle_language': 'pt-BR'});
      // The row (and the confirmation, which says the same).
      expect(find.bySemanticsLabel('Sous-titres : Portugais (Brésil)'), findsWidgets);

      await tapRow(tester, 'Langue audio préférée : Version originale');
      await tester.tap(find.text('Français').last);
      await tester.pumpAndSettle();
      expect(auth.updates.last, {'audio_language': 'fr'});

      // Back to subtitles off.
      await tapRow(tester, 'Sous-titres : Portugais (Brésil)');
      await tester.tap(find.text('Désactivés').last);
      await tester.pumpAndSettle();
      expect(auth.updates.last, {'subtitle_language': null});
    });
  });

  group('recent searches', () {
    ProviderContainer containerWith(FakeHistory history) {
      final container = ProviderContainer(
        overrides: [
          searchHistoryRepositoryProvider.overrideWithValue(history),
          sessionProvider.overrideWith(() => WithProfile(const Profile(id: 2, name: 'Léa'))),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    List<String> queries(ProviderContainer c) => c.read(recentSearchesProvider).value!.map((s) => s.query).toList();

    test('come from the API, and new ones go back to it', () async {
      final history = FakeHistory();
      final container = containerWith(history);
      await container.read(recentSearchesProvider.future);
      expect(queries(container), ['Dune']);

      final notifier = container.read(recentSearchesProvider.notifier);
      await notifier.add('orb');
      await notifier.add('orbite');
      // "orbite" replaces "orb", typed just before; "Dune" stays.
      expect(queries(container), ['orbite', 'Dune']);
      // Searched again with another case: moved to the top, once.
      await notifier.add('DUNE');
      expect(queries(container), ['DUNE', 'orbite']);
      expect(history.calls, ['add orb', 'add orbite', 'add DUNE']);

      await notifier.remove(container.read(recentSearchesProvider).value!.last);
      expect(queries(container), ['DUNE']);
      await notifier.clear();
      expect(queries(container), isEmpty);
      expect(history.calls.sublist(3), [startsWith('remove '), 'clear']);
    });

    test('stay on screen when the API cannot be reached', () async {
      final history = FakeHistory()..fail = true;
      final container = containerWith(history);
      await container.read(recentSearchesProvider.future);

      await container.read(recentSearchesProvider.notifier).add('Orbite');
      expect(queries(container), ['Orbite', 'Dune']);
    });
  });

  group('player data', () {
    test('reads the moments to skip and finds the one playing', () async {
      final adapter = FakeAdapter({
        'data': {
          'intro': [
            {'start_ms': null, 'end_ms': 90000},
          ],
          'recap': <Object>[],
          'credits': [
            {'start_ms': 3600000, 'end_ms': null},
          ],
          'preview': <Object>[],
        },
      });
      final segments = await repository(adapter).segments((type: MediaType.tv, id: 1399, season: 1, episode: 2));

      expect(adapter.requests.single.path, '/catalog/tv/1399/season/1/episode/2/segments');
      expect(segments.at(const Duration(seconds: 30))?.kind, SkipKind.intro);
      expect(segments.at(const Duration(seconds: 90)), isNull);
      expect(segments.at(const Duration(hours: 1, minutes: 2))?.kind, SkipKind.credits);
      // No end: the player goes to the end (next episode).
      expect(segments.at(const Duration(hours: 1, minutes: 2))?.end, isNull);

      const profile = Profile(id: 2, name: 'Léa', skipCredits: true);
      expect(SkipKind.credits.autoFor(profile), isTrue);
      expect(SkipKind.intro.autoFor(profile), isFalse);
      expect(SkipKind.intro.buttonLabel, 'Passer le générique');
    });

    test('finds subtitles and downloads one as WebVTT', () async {
      final search = FakeAdapter({
        'data': [
          {
            'file_id': 7,
            'language': 'fr',
            'release': 'Dune.2024',
            'hearing_impaired': true,
            'ai_translated': false,
            'downloads': 12,
          },
        ],
      });
      final options = await repository(search)
          .subtitles((type: MediaType.movie, id: 550, season: null, episode: null), languages: ['fr', 'en']);

      expect(search.requests.single.path, '/catalog/movie/550/subtitles');
      expect(search.requests.single.queryParameters['languages'], 'fr,en');
      expect(options.single.fileId, 7);
      expect(options.single.hearingImpaired, isTrue);

      final file = FakeAdapter('WEBVTT\n\n00:01.000 --> 00:02.000\nBonjour\n');
      expect(await repository(file).subtitleFile(7), startsWith('WEBVTT'));
      expect(file.requests.single.path, '/catalog/subtitles/7');
    });
  });

  group('stream providers', () {
    test('a failed source says why, in the words of the plug-in system or of the API', () {
      expect(
        scraperFailureReason(const ScraperException("Le moteur des plug-ins n'a pas pu démarrer sur cet appareil.")),
        "Le moteur des plug-ins n'a pas pu démarrer sur cet appareil.",
      );
      expect(scraperFailureReason(const ApiException('Trop de requêtes.')), 'Trop de requêtes.');
      expect(scraperFailureReason(const ScraperException('  ')), isNull);
      expect(scraperFailureReason(StateError('x')), isNull);
      expect(scraperFailureReason(null), isNull);
    });

    const item = (type: MediaType.movie, id: 550, season: null, episode: null);
    const tvItem = (type: MediaType.tv, id: 1399, season: 1, episode: 2);

    ProviderContainer containerWith({List<ScraperRepo>? repos, FakeScraperRuntime? runtime, RoutingAdapter? adapter}) {
      final container = scraperContainer(
        repos: repos,
        runtime: runtime,
        http: FakeScraperHttp({'https://repo.test/providers/films.js': 'module.exports = {};'}),
        api: adapter == null ? null : routingClient(adapter),
      );
      addTearDown(container.dispose);
      return container;
    }

    // Riverpod 3 disposes a provider as soon as nothing listens to it. Keep a listener
    // alive and wait for the value to settle, so a slow request is not cancelled.
    Future<AsyncValue<T>> read<T>(ProviderContainer container, FutureProvider<T> provider) {
      final completer = Completer<AsyncValue<T>>();
      final sub = container.listen<AsyncValue<T>>(provider, (_, next) {
        if (!completer.isCompleted && (next.hasValue || next.hasError)) {
          completer.complete(next);
        }
      }, fireImmediately: true);
      addTearDown(sub.close);
      return completer.future;
    }

    test('lists the scrapers that handle the title, from every repository', () async {
      final repo = testRepo();

      final state = await read(containerWith(repos: [repo]), sourceProvidersProvider(item));

      // The series scraper does not handle a movie.
      expect(state.requireValue.map((p) => p.name), ['Films libres', 'Tout']);
      expect(state.requireValue.first.id, repo.scrapers[0].providerId);

      final series = await read(containerWith(repos: [repo]), sourceProvidersProvider(tvItem));
      expect(series.requireValue.map((p) => p.name), ['Séries libres', 'Tout']);
    });

    test('follows the order of the repositories, and leaves out a repository turned off', () async {
      final both = await read(containerWith(repos: [otherRepo(), testRepo()]), sourceProvidersProvider(item));
      expect(both.requireValue.map((p) => p.name), ['Autre source', 'Films libres', 'Tout']);

      final off = await read(
        containerWith(repos: [otherRepo(), testRepo().copyWith(enabled: false)]),
        sourceProvidersProvider(item),
      );
      expect(off.requireValue.map((p) => p.name), ['Autre source']);
    });

    test('a scraper of a repository turned off gives nothing, and does not run', () async {
      final repo = testRepo().copyWith(enabled: false);
      final runtime = FakeScraperRuntime();

      final state = await read(
        containerWith(repos: [repo], runtime: runtime),
        providerSourcesProvider((item: item, provider: repo.scrapers[0].providerId)),
      );

      expect(state.requireValue, isEmpty);
      expect(runtime.calls, isEmpty);
    });

    test('has no provider when no plug-in is installed', () async {
      final container = containerWith();

      expect((await read(container, sourceProvidersProvider(item))).requireValue, isEmpty);
    });

    test('never asks the API for providers: the plug-ins are on the device', () async {
      final adapter = RoutingAdapter([]);
      final container = containerWith(repos: [testRepo()], adapter: adapter);

      await read(container, sourceProvidersProvider(item));

      expect(adapter.requests, isEmpty);
    });

    test('runs the chosen scraper, and maps its streams to playable sources', () async {
      final repo = testRepo();
      final runtime = FakeScraperRuntime()
        ..answer = (code, params) => const [
          ScraperStream(url: 'https://cdn.test/a.m3u8', name: 'Serveur 1', quality: '1080p'),
          ScraperStream(url: 'https://cdn.test/b.mp4', headers: {'Referer': 'https://x.test/'}),
        ];
      final container = containerWith(repos: [repo], runtime: runtime);

      final state = await read(
        container,
        providerSourcesProvider((item: item, provider: repo.scrapers[0].providerId)),
      );

      final links = state.requireValue;
      expect(links.map((l) => l.name), ['Serveur 1 · 1080p', 'Films libres']);
      expect(links.first.provider, repo.scrapers[0].providerId);
      expect(links.first.stream, 'https://cdn.test/a.m3u8');
      expect(links.first.streamType, 'm3u8');
      expect(links.last.headers, {'Referer': 'https://x.test/'});
      expect(runtime.calls.single.params.tmdbId, '550');
    });

    test('a scraper that was removed gives nothing, not an error', () async {
      final state = await read(
        containerWith(repos: [testRepo()]),
        providerSourcesProvider((item: item, provider: 'scraper:disparu:films')),
      );

      expect(state.hasError, isFalse);
      expect(state.requireValue, isEmpty);
    });

    test('a scraper that fails surfaces as an error', () async {
      final runtime = FakeScraperRuntime()..error = const ScraperException('Le plug-in a échoué.');
      final repo = testRepo();

      final state = await read(
        containerWith(repos: [repo], runtime: runtime),
        providerSourcesProvider((item: item, provider: repo.scrapers[0].providerId)),
      );

      expect(state.hasError, isTrue);
      expect(state.error, isA<ScraperException>());
    });
  });
}

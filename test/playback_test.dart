import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/playback/playback.dart';
import 'package:vixeo/features/playback/player_screen.dart';
import 'package:vixeo/features/profiles/profile_preferences_screen.dart';
import 'package:vixeo/features/search/search_history.dart';

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false);

class WithProfile extends SessionController {
  WithProfile(this.profile);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', user: davy, profile: profile);
}

/// The API's profile update, in memory.
class FakeProfiles extends AuthRepository {
  FakeProfiles() : super(ApiClient(token: () => null, profileId: () => null));

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
  FakeHistory() : super(ApiClient(token: () => null, profileId: () => null));

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
    profileId: () => 2,
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
  profileId: () => 2,
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

    test('resolves a player link into a playable stream, with its headers', () async {
      final adapter = FakeAdapter({
        'data': {
          'stream': 'https://delivery.voe.sx/hls/master.m3u8',
          'stream_type': 'm3u8',
          'extractor': 'voe',
          'headers': {'Referer': 'https://voe.sx/', 'User-Agent': 'Vixeo'},
          'subtitles': <Object>[],
        },
      });

      final resolved = await repository(adapter).resolve('https://voe.sx/e/abc');

      final request = adapter.requests.single;
      expect(request.path, '/catalog/resolve');
      expect(request.method, 'POST');
      expect(request.data, {'url': 'https://voe.sx/e/abc'});
      expect(resolved.stream, 'https://delivery.voe.sx/hls/master.m3u8');
      expect(resolved.streamType, 'm3u8');
      expect(resolved.extractor, 'voe');
      expect(resolved.headers['Referer'], 'https://voe.sx/');
    });

    test('surfaces the API error when a link cannot be resolved', () async {
      final adapter = FakeAdapter({'message': 'Cette source n’est pas lisible.'}, status: 502);

      // A 502 from the API: the player shows the French message, no raw URL fallback.
      await expectLater(
        repository(adapter).resolve('https://unknown-host.tld/e/xyz'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Cette source n’est pas lisible.')),
      );
    });
  });

  group('stream providers', () {
    const item = (type: MediaType.movie, id: 550, season: null, episode: null);

    ProviderContainer containerWith(RoutingAdapter adapter) {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(routingClient(adapter))],
      );
      addTearDown(container.dispose);
      return container;
    }

    // Riverpod 3 disposes a provider as soon as nothing listens to it. Keep a listener
    // alive and wait for the value to settle, so a slow request is not cancelled.
    Future<AsyncValue<T>> read<T>(ProviderContainer container, FutureProvider<T> provider) {
      final completer = Completer<AsyncValue<T>>();
      final sub = container.listen<AsyncValue<T>>(
        provider,
        (_, next) {
          if (!completer.isCompleted && (next.hasValue || next.hasError)) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);
      return completer.future;
    }

    Future<List<StreamSource>> linksOf(ProviderContainer c, FutureProvider<List<StreamSource>> p) async =>
        (await read(c, p)).requireValue;

    test('lists the providers the API declares', () async {
      final adapter = RoutingAdapter([
        ('/catalog/sources/providers', {
          'data': [
            {'id': 'frenchstream', 'name': 'FrenchStream'},
            {'id': 'wiflix', 'name': 'Wiflix'},
            {'id': 'frembed', 'name': 'Frembed'},
          ],
        }, 200),
      ]);

      final state = await read(containerWith(adapter), sourceProvidersProvider(item));

      expect(state.requireValue.map((p) => p.id), ['frenchstream', 'wiflix', 'frembed']);
      expect(adapter.requests.single.path, '/catalog/sources/providers');
    });

    test('falls back to the known providers when the API list fails', () async {
      final adapter = RoutingAdapter([
        ('/catalog/sources/providers', {'message': 'Boom'}, 500),
      ]);

      // The panel must still show every provider, even before the list is known.
      final state = await read(containerWith(adapter), sourceProvidersProvider(item));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ApiException>());
      expect(kSourceProvidersFallback.map((p) => p.id), ['frenchstream', 'wiflix', 'frembed']);
    });

    test('asks the API for a single provider, and maps its links', () async {
      final adapter = RoutingAdapter([
        ('/catalog/movie/550/sources', {
          'data': [
            {'provider': 'wiflix', 'name': 'Wiflix (VF)', 'url': 'https://voe.sx/e/w'},
          ],
        }, 200),
      ]);

      final links = await linksOf(
        containerWith(adapter),
        providerSourcesProvider((item: item, provider: 'wiflix')),
      );

      expect(links.single.name, 'Wiflix (VF)');
      final request = adapter.requests.single;
      expect(request.path, '/catalog/movie/550/sources');
      expect(request.queryParameters['provider'], 'wiflix');
    });

    test('an empty provider resolves to an empty list, not an error', () async {
      final adapter = RoutingAdapter([
        ('/catalog/movie/550/sources', {'data': <Object>[]}, 200),
      ]);

      final state = await read(
        containerWith(adapter),
        providerSourcesProvider((item: item, provider: 'frembed')),
      );

      expect(state.hasError, isFalse);
      expect(state.requireValue, isEmpty);
    });

    test('a provider the API cannot reach surfaces as an error', () async {
      final adapter = RoutingAdapter([
        ('/catalog/movie/550/sources', {'message': 'Ce fournisseur est momentanément indisponible.'}, 503),
      ]);

      final state = await read(
        containerWith(adapter),
        providerSourcesProvider((item: item, provider: 'wiflix')),
      );

      expect(state.hasError, isTrue);
      expect(state.error, isA<ApiException>());
    });
  });
}

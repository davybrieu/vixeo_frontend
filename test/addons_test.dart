import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/local_store.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/addons/addons_screen.dart';
import 'package:vixeo/features/addons/scraper_guard.dart';
import 'package:vixeo/features/addons/scraper_host.dart';
import 'package:vixeo/features/addons/scraper_http.dart';
import 'package:vixeo/features/addons/scraper_models.dart';
import 'package:vixeo/features/addons/scrapers.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/playback/engine/engine_factory.dart';
import 'package:vixeo/features/playback/playback.dart';
import 'package:vixeo/features/playback/player_screen.dart';

import 'player_engine_test.dart' show FakeEngine, SignedOut, settle, closePlayer;
import 'scraper_fakes.dart';
import 'tv_repository_test.dart' show RoutingAdapter;

const movie = (type: MediaType.movie, id: 550, season: null, episode: null);
const episode = (type: MediaType.tv, id: 1399, season: 2, episode: 3);

final _files = {
  repoUrl: jsonEncode(manifestJson()),
  'https://repo.test/providers/films.js': 'module.exports = { films: 1 };',
  'https://repo.test/providers/series.js': 'module.exports = { series: 1 };',
};

ApiClient apiWith(RoutingAdapter adapter) => ApiClient(
  token: () => 't',
  profileId: () => 2,
  dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
);

/// Keeps the repositories loaded (Riverpod 3 disposes what nothing listens to).
Future<List<ScraperRepo>> reposOf(ProviderContainer container) async {
  final sub = container.listen(scraperReposProvider, (_, _) {});
  addTearDown(sub.close);
  return container.read(scraperReposProvider.future);
}

ProviderContainer keptContainer({
  List<ScraperRepo>? repos,
  FakeScraperHttp? http,
  FakeScraperRuntime? runtime,
  MemoryLocalStore? store,
  ApiClient? api,
  List<Override> extraOverrides = const [],
}) {
  final container = scraperContainer(
    repos: repos,
    http: http,
    runtime: runtime,
    store: store,
    api: api,
    extraOverrides: extraOverrides,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('installed repositories', () {
    test('start empty', () async {
      expect(await reposOf(keptContainer()), isEmpty);
    });

    test('install a repository from its address, and keep it on the device for the account', () async {
      final store = MemoryLocalStore();
      final container = keptContainer(store: store, http: FakeScraperHttp(_files));
      await reposOf(container);

      // A folder address: manifest.json is added.
      final repo = await container.read(scraperReposProvider.notifier).add('  https://repo.test ');

      expect(repo.url, repoUrl);
      expect(repo.name, 'Dépôt test');
      expect(container.read(scraperReposProvider).value!.single.scrapers, hasLength(3));
      expect(ScraperRepo.decodeList(store.values[ScraperRepos.keyFor(7)]).single.url, repoUrl);

      // Another start of the app: the repository is still there.
      final again = keptContainer(store: store);
      expect((await reposOf(again)).single.scrapers.map((s) => s.id), ['films', 'series', 'tout']);
    });

    test('refuse an address, a repository or a manifest that cannot be used, and say why', () async {
      final container = keptContainer(
        http: FakeScraperHttp({
          ..._files,
          'https://empty.test/manifest.json': '{"scrapers":[]}',
          'https://text.test/manifest.json': '<html>',
        }),
      );
      await reposOf(container);
      final repos = container.read(scraperReposProvider.notifier);

      Future<String> failure(String input) async {
        try {
          await repos.add(input);
        } on ScraperException catch (e) {
          return e.message;
        }
        return 'pas d’erreur';
      }

      expect(await failure('ftp://repo.test/manifest.json'), 'Seules les adresses https:// sont acceptées.');
      expect(await failure('https://127.0.0.1/manifest.json'), startsWith('Adresse refusée'));
      expect(await failure('https://absent.test/manifest.json'), 'Téléchargement impossible (erreur 404).');
      expect(await failure('https://text.test/manifest.json'), "Ce n'est pas le manifeste d'un dépôt de plug-ins.");
      expect(await failure('https://empty.test/manifest.json'), 'Ce dépôt ne contient aucun plug-in utilisable.');
      expect(container.read(scraperReposProvider).value, isEmpty);

      await repos.add(repoUrl);
      expect(await failure(repoUrl), 'Ce dépôt est déjà installé.');
      expect(container.read(scraperReposProvider).value, hasLength(1));
    });

    test('move a repository, keep the order on the device, and ignore a move that makes no sense', () async {
      final store = MemoryLocalStore();
      final other = otherRepo();
      final container = keptContainer(repos: [testRepo(), other], store: store);
      await reposOf(container);
      final repos = container.read(scraperReposProvider.notifier);
      List<String> order() => [for (final r in container.read(scraperReposProvider).value!) r.name];

      await repos.move(other.id, 0);
      expect(order(), ['Autre dépôt', 'Dépôt test']);
      await repos.move(other.id, 2);
      await repos.move(other.id, -1);
      await repos.move('inconnu', 1);
      expect(order(), ['Autre dépôt', 'Dépôt test']);

      // Another start of the app: the order is still there.
      expect((await reposOf(keptContainer(store: store))).map((r) => r.name), ['Autre dépôt', 'Dépôt test']);
    });

    test('turn a repository off and on again, and keep the choice on the device', () async {
      final repo = testRepo();
      final store = MemoryLocalStore();
      final container = keptContainer(repos: [repo], store: store);
      await reposOf(container);
      final repos = container.read(scraperReposProvider.notifier);
      expect(container.read(scraperReposProvider).value!.single.enabled, isTrue);

      await repos.setEnabled(repo.id, false);
      expect(container.read(scraperReposProvider).value!.single.enabled, isFalse);
      expect((await reposOf(keptContainer(store: store))).single.enabled, isFalse);

      await repos.setEnabled(repo.id, true);
      expect((await reposOf(keptContainer(store: store))).single.enabled, isTrue);
    });

    test('read the manifest again without losing the person’s choices', () async {
      final repo = testRepo().copyWith(enabled: false);
      final changed = {
        ..._files,
        repoUrl: jsonEncode({
          'name': 'Dépôt test',
          'scrapers': [
            ...(manifestJson()['scrapers']! as List),
            {'id': 'neuf', 'name': 'Neuf', 'filename': 'providers/neuf.js'},
          ],
        }),
      };
      final container = keptContainer(repos: [repo], http: FakeScraperHttp(changed));
      await reposOf(container);
      final repos = container.read(scraperReposProvider.notifier);
      await repos.refresh(repo.id);

      final updated = container.read(scraperReposProvider).value!.single;
      expect(updated.scrapers.map((s) => s.id), ['films', 'series', 'tout', 'neuf']);
      expect(updated.enabled, isFalse);
    });

    test('remove a repository', () async {
      final repo = testRepo();
      final store = MemoryLocalStore();
      final container = keptContainer(repos: [repo], store: store);
      await reposOf(container);

      await container.read(scraperReposProvider.notifier).remove(repo.id);

      expect(container.read(scraperReposProvider).value, isEmpty);
      expect(store.values.containsKey(ScraperRepos.keyFor(7)), isFalse);
    });
  });

  group('asking a scraper for streams', () {
    test('on the device: downloads its code once, runs it with the title, returns its streams', () async {
      final repo = testRepo();
      final http = FakeScraperHttp(_files);
      final runtime = FakeScraperRuntime()
        ..answer = (code, params) => [ScraperStream(url: 'https://cdn.test/${params.tmdbId}.m3u8')];
      final container = keptContainer(repos: [repo], http: http, runtime: runtime);
      final service = container.read(scraperServiceProvider);

      final streams = await service.streams(repo, repo.scrapers[0], movie);
      await service.streams(repo, repo.scrapers[0], movie);

      expect(streams.single.url, 'https://cdn.test/550.m3u8');
      expect(runtime.calls.first.code, 'module.exports = { films: 1 };');
      expect(runtime.calls.first.params.tmdbId, '550');
      expect(runtime.calls.first.params.mediaType, 'movie');
      expect(runtime.calls.first.params.season, isNull);
      expect(http.requests.where((r) => r.url.endsWith('films.js')), hasLength(1));
    });

    test('gives the season and the episode of a series, and none for a movie', () async {
      final repo = testRepo();
      final runtime = FakeScraperRuntime();
      final container = keptContainer(repos: [repo], http: FakeScraperHttp(_files), runtime: runtime);
      final service = container.read(scraperServiceProvider);

      await service.streams(repo, repo.scrapers[1], episode);

      final params = runtime.calls.single.params;
      expect((params.tmdbId, params.mediaType, params.season, params.episode), ('1399', 'tv', 2, 3));
    });

    test('says so when the code cannot be downloaded, or the scraper fails', () async {
      final repo = testRepo();
      final runtime = FakeScraperRuntime();
      final container = keptContainer(repos: [repo], http: FakeScraperHttp({}), runtime: runtime);
      final service = container.read(scraperServiceProvider);

      await expectLater(
        service.streams(repo, repo.scrapers[0], movie),
        throwsA(isA<ScraperException>().having((e) => e.message, 'message', 'Téléchargement impossible (erreur 404).')),
      );

      runtime.error = const ScraperException('boom');
      final working = keptContainer(repos: [repo], http: FakeScraperHttp(_files), runtime: runtime);
      await expectLater(
        working.read(scraperServiceProvider).streams(repo, repo.scrapers[0], movie),
        throwsA(isA<ScraperException>().having((e) => e.message, 'message', 'boom')),
      );
    });

    test('runs at most six scrapers at once', () async {
      final repo = testRepo();
      final runtime = _SlowRuntime();
      final container = keptContainer(repos: [repo], http: FakeScraperHttp(_files), runtime: runtime);
      final service = container.read(scraperServiceProvider);

      expect(ScraperService.maxParallel, 6);
      final all = [for (var i = 0; i < 10; i++) service.streams(repo, repo.scrapers[0], movie)];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.running, ScraperService.maxParallel);

      await Future.wait(all);
      expect(runtime.started, 10);
      expect(runtime.peak, ScraperService.maxParallel);
    });

    test('writes what a run did in the journal of its source: requests, console, end', () async {
      final repo = testRepo();
      final container = keptContainer(repos: [repo], http: FakeScraperHttp(_files), runtime: _ChattyRuntime());
      final journal = container.read(scraperJournalProvider);

      final streams = await container
          .read(scraperServiceProvider)
          .streams(repo, repo.scrapers[0], movie, journal: journal.start('scraper:x'));

      expect(streams, hasLength(1));
      final lines = journal.of('scraper:x').join('\n');
      expect(lines, contains('movie 550'));
      expect(lines, contains('GET $repoUrl → 200'));
      expect(lines, contains('GET https://absent.test/x → 404'));
      expect(lines, contains('[log] [Films] recherche'));
      expect(lines, contains('fin : 1 flux'));
      expect(journal.of('scraper:autre'), isEmpty);
    });

    test('a journal keeps the last run only, and stops growing', () {
      final journal = ScraperJournal();
      journal.start('scraper:x')('ancien');
      final write = journal.start('scraper:x');
      for (var i = 0; i < ScraperJournal.maxLines + 50; i++) {
        write('ligne $i ${'x' * 400}');
      }
      final lines = journal.of('scraper:x');
      expect(lines, hasLength(ScraperJournal.maxLines + 1));
      expect(lines.any((l) => l.contains('ancien')), isFalse);
      expect(lines.last, contains('journal coupé'));
      expect(lines.first.length, lessThan(ScraperJournal.maxLineLength + 20));
    });

    test('gives a scraper its Nuvio id (SCRAPER_ID): the manifest address and its own id', () async {
      final repo = testRepo();
      final runtime = FakeScraperRuntime();
      final container = keptContainer(repos: [repo], http: FakeScraperHttp(_files), runtime: runtime);

      await container.read(scraperServiceProvider).streams(repo, repo.scrapers[0], movie);

      expect(runtime.calls.single.params.scraperId, '$repoUrl:films');
      expect(runtime.calls.single.params.toJson(), containsPair('scraperId', '$repoUrl:films'));
      expect(runtime.calls.single.params.toJson(), containsPair('settings', isEmpty));
    });
  });

  group('« Plug-ins »', () {
    Future<ProviderContainer> open(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildVixeoTheme(), home: const AddonsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    List<String> names(ProviderContainer c) => [for (final r in c.read(scraperReposProvider).value!) r.name];

    testWidgets('says that Vixeo provides no repository, and that none is installed', (tester) async {
      await open(tester, keptContainer());

      expect(find.text('Plug-ins'), findsOneWidget);
      expect(find.textContaining('Vixeo n’en fournit aucun'), findsOneWidget);
      expect(find.text('Aucun dépôt installé.'), findsOneWidget);
    });

    testWidgets('installs a repository from its address, and says why one is refused', (tester) async {
      final container = await open(tester, keptContainer(http: FakeScraperHttp(_files)));

      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(find.text("Collez l'adresse du dépôt."), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ftp://repo.test/manifest.json');
      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(find.text('Seules les adresses https:// sont acceptées.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  https://repo.test/manifest.json ');
      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(find.text('Dépôt installé : Dépôt test'), findsOneWidget);
      expect(find.text('repo.test · v1.0.0'), findsOneWidget);
      expect(find.bySemanticsLabel('Dépôt test, activé'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer le dépôt : Dépôt test'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(container.read(scraperReposProvider).value, hasLength(1));
    });

    testWidgets('lists the repositories only, never their scrapers', (tester) async {
      await open(tester, keptContainer(repos: [testRepo(), otherRepo()]));

      expect(find.text('Dépôt test'), findsOneWidget);
      expect(find.text('repo.test · v1.0.0'), findsOneWidget);
      expect(find.text('Autre dépôt'), findsOneWidget);
      expect(find.text('autre.test'), findsOneWidget);
      for (final scraper in ['Films libres', 'Séries libres', 'Tout', 'Autre source', 'Des films.']) {
        expect(find.textContaining(scraper), findsNothing, reason: scraper);
      }
      expect(find.textContaining('v1.2.0'), findsNothing);
    });

    testWidgets('turns a repository off, then on again', (tester) async {
      final container = await open(tester, keptContainer(repos: [testRepo()]));
      bool enabled() => container.read(scraperReposProvider).value!.single.enabled;

      await tester.tap(find.bySemanticsLabel('Dépôt test, activé'));
      await tester.pumpAndSettle();
      expect(enabled(), isFalse);
      expect(find.bySemanticsLabel('Dépôt test, désactivé'), findsOneWidget);
      // Still installed.
      expect(find.text('Dépôt test'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Dépôt test, désactivé'));
      await tester.pumpAndSettle();
      expect(enabled(), isTrue);
    });

    testWidgets('moves a repository up and down', (tester) async {
      final container = await open(tester, keptContainer(repos: [testRepo(), otherRepo()]));

      await tester.tap(find.bySemanticsLabel('Monter : Autre dépôt'));
      await tester.pumpAndSettle();
      expect(names(container), ['Autre dépôt', 'Dépôt test']);

      await tester.tap(find.bySemanticsLabel('Descendre : Autre dépôt'));
      await tester.pumpAndSettle();
      expect(names(container), ['Dépôt test', 'Autre dépôt']);
    });

    testWidgets('reads the repository again, and removes it after a confirmation', (tester) async {
      final more = {
        ..._files,
        repoUrl: jsonEncode({
          'name': 'Dépôt test',
          'scrapers': [
            ...(manifestJson()['scrapers']! as List),
            {'id': 'neuf', 'name': 'Neuf', 'filename': 'providers/neuf.js'},
          ],
        }),
      };
      final container = await open(tester, keptContainer(repos: [testRepo()], http: FakeScraperHttp(more)));

      await tester.tap(find.bySemanticsLabel('Mettre à jour le dépôt : Dépôt test'));
      await tester.pumpAndSettle();
      expect(find.text('Dépôt mis à jour'), findsOneWidget);
      expect(container.read(scraperReposProvider).value!.single.scrapers, hasLength(4));

      await tester.tap(find.bySemanticsLabel('Retirer le dépôt : Dépôt test'));
      await tester.pumpAndSettle();
      expect(find.text('Retirer le dépôt'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();
      expect(container.read(scraperReposProvider).value, hasLength(1));

      await tester.tap(find.bySemanticsLabel('Retirer le dépôt : Dépôt test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();
      expect(find.text('Dépôt retiré'), findsOneWidget);
      expect(find.text('Aucun dépôt installé.'), findsOneWidget);
      expect(container.read(scraperReposProvider).value, isEmpty);
    });

    testWidgets('says why a repository could not be read again', (tester) async {
      await open(tester, keptContainer(repos: [testRepo()], http: FakeScraperHttp({})));

      await tester.tap(find.bySemanticsLabel('Mettre à jour le dépôt : Dépôt test'));
      await tester.pumpAndSettle();

      expect(find.text('Téléchargement impossible (erreur 404).'), findsOneWidget);
      expect(find.text('repo.test · v1.0.0'), findsOneWidget);
    });
  });

  group('player', () {
    Future<void> openPanel(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedOut.new),
            playbackRepositoryProvider.overrideWithValue(_NoResolve()),
            playerEngineFactoryProvider.overrideWithValue((source) => FakeEngine()),
            sourceProvidersProvider.overrideWith((ref, item) async => const <SourceProvider>[]),
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const PlayerScreen(type: MediaType.movie, id: 550),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('says that no plug-in is installed when there is none', (tester) async {
      await openPanel(tester);

      expect(find.text("Aucun plug-in n'est installé."), findsOneWidget);

      await closePlayer(tester);
    });

    testWidgets('says that the plug-ins are turned off when every repository is, and runs none', (tester) async {
      final runtime = FakeScraperRuntime();
      final container = keptContainer(
        repos: [testRepo().copyWith(enabled: false)],
        http: FakeScraperHttp(_files),
        runtime: runtime,
        extraOverrides: [
          playbackRepositoryProvider.overrideWithValue(_NoResolve()),
          playerEngineFactoryProvider.overrideWithValue((source) => FakeEngine()),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const PlayerScreen(type: MediaType.movie, id: 550),
          ),
        ),
      );
      await settle(tester);

      expect(find.text(pluginsDisabledMessage), findsOneWidget);
      expect(find.text('Films libres'), findsNothing);
      expect(runtime.calls, isEmpty);

      await closePlayer(tester);
    });

    testWidgets('plays a scraper’s stream as it is, with its headers', (
      tester,
    ) async {
      final engine = FakeEngine();
      final playback = _NoResolve();
      final repo = testRepo();
      final runtime = FakeScraperRuntime()
        ..answer = (code, params) => const [
          ScraperStream(
            url: 'https://cdn.test/fc.m3u8',
            name: 'Serveur 1',
            quality: '1080p',
            headers: {'Referer': 'https://cdn.test/'},
          ),
        ];
      final container = keptContainer(
        repos: [repo],
        http: FakeScraperHttp(_files),
        runtime: runtime,
        extraOverrides: [
          playbackRepositoryProvider.overrideWithValue(playback),
          playerEngineFactoryProvider.overrideWithValue((source) => engine),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const PlayerScreen(type: MediaType.movie, id: 550),
          ),
        ),
      );
      await settle(tester);

      // The series scraper does not handle a movie: only the two others are offered.
      expect(find.text('Séries libres'), findsNothing);
      await tester.tap(find.text('Films libres'));
      await settle(tester);
      await tester.tap(find.text('Serveur 1 · 1080p'));
      await settle(tester);

      expect(runtime.calls.single.params.tmdbId, '550');
      expect(engine.opened?.url, 'https://cdn.test/fc.m3u8');
      expect(engine.opened?.isHls, isTrue);
      expect(engine.opened?.headers, {'Referer': 'https://cdn.test/'});
      expect(engine.plays, 1);

      await closePlayer(tester);
    });
  });
}

/// A runtime that takes a moment, and counts how many runs overlap.
/// Asks for two files and writes in its console, like a real scraper.
class _ChattyRuntime extends FakeScraperRuntime {
  @override
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  }) async {
    onLog?.call('log', '[Films] recherche');
    await fetch(const ScraperHttpRequest(url: repoUrl));
    await fetch(const ScraperHttpRequest(url: 'https://absent.test/x'));
    return const [ScraperStream(url: 'https://cdn.test/a.m3u8')];
  }
}

class _SlowRuntime extends FakeScraperRuntime {
  int running = 0;
  int started = 0;
  int peak = 0;

  @override
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  }) async {
    started++;
    running++;
    if (running > peak) peak = running;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    running--;
    return const [];
  }
}

/// The player's data without the network (no subtitles).
class _NoResolve extends PlaybackRepository {
  _NoResolve() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<List<SubtitleOption>> subtitles(PlaybackItem item, {List<String>? languages}) async => const [];
}

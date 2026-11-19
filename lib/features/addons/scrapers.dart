/// Plug-ins: repositories of JavaScript scrapers, façon Nuvio (`docs/scrapers.md`).
///
/// This file is the app's logic for them, in four parts:
/// - [ScraperRepos]: the installed repositories, kept **on the device**
///   (`LocalStore`), per account, in the person's order, each on or off. Execution mode comes
///   from the manifest.
/// - [ScraperLoader]: downloads manifests and scrapers' code (never run here).
/// - [ScraperService]: asks one scraper for the streams of a title, on the device or on the server
///   according to the repository's declared mode.
/// - the providers that wire them to the player's sources panel (`player_screen.dart`).
///
/// The catalog is not concerned: plug-ins only give **sources** (demande du développeur).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/local_store.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../playback/playback.dart' show PlaybackItem;
import 'scraper_guard.dart';
import 'scraper_http.dart';
import 'scraper_models.dart';
import 'scraper_platform.dart';
import 'scraper_runtime.dart';

/// How requests leave the app (tests replace it).
final scraperHttpProvider = Provider<ScraperHttp>((ref) => createScraperHttp(ref.read(apiClientProvider)));

/// Where scrapers' JavaScript runs on this platform (tests replace it).
final scraperRuntimeProvider = Provider<ScraperRuntime>((ref) => createLocalScraperRuntime());

final scraperLoaderProvider = Provider<ScraperLoader>((ref) => ScraperLoader(ref.read(scraperHttpProvider)));

final scraperServiceProvider = Provider<ScraperService>((ref) => ScraperService(ref));

/// The installed repositories (« Paramètres » → « Plug-ins »), in the order the person chose.
final scraperReposProvider = AsyncNotifierProvider<ScraperRepos, List<ScraperRepo>>(ScraperRepos.new);

class ScraperRepos extends AsyncNotifier<List<ScraperRepo>> {
  static String keyFor(int userId) => 'vixeo.scrapers.$userId';

  @override
  Future<List<ScraperRepo>> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s.user?.id));
    if (userId == null) return const [];
    try {
      return ScraperRepo.decodeList(await ref.read(localStoreProvider).read(keyFor(userId)));
    } catch (_) {
      return const [];
    }
  }

  /// Installs the repository whose manifest is at [input]. Throws a [ScraperException] (in French)
  /// when the address is not usable, the repository already installed, or its manifest unusable.
  Future<ScraperRepo> add(String input) async {
    final url = ScraperRepo.normalizeUrl(input);
    if ((await future).any((r) => r.url == url)) throw const ScraperException('Ce dépôt est déjà installé.');
    final manifest = await ref.read(scraperLoaderProvider).manifest(url);
    final repo = ScraperRepo.fromManifest(url, manifest);
    await _update((repos) => repos.any((r) => r.url == url) ? repos : [...repos, repo]);
    return repo;
  }

  Future<void> remove(String repositoryId) async {
    await _update((repos) => [
      for (final repo in repos)
        if (repo.id != repositoryId) repo,
    ]);
    ref.read(scraperLoaderProvider).forgetCode();
  }

  /// Reads the manifest again: the scrapers become the manifest's; on or off stays.
  Future<void> refresh(String repositoryId) async {
    final repo = (await future).where((r) => r.id == repositoryId).firstOrNull;
    if (repo == null) return;
    final loader = ref.read(scraperLoaderProvider);
    final manifest = await loader.manifest(repo.url);
    loader.forgetCode();
    await _update((repos) => [for (final r in repos) r.id == repositoryId ? r.updatedWith(manifest) : r]);
  }

  /// Turns a repository on or off: off, it stays installed but gives no sources.
  Future<void> setEnabled(String repositoryId, bool enabled) => _update(
    (repos) => [for (final r in repos) r.id == repositoryId ? r.copyWith(enabled: enabled) : r],
  );

  /// Moves a repository to [to] in the list: the sources panel lists the scrapers of the first
  /// repository first. A move outside the list, or of an unknown repository, changes nothing.
  Future<void> move(String repositoryId, int to) => _update((repos) {
    final from = repos.indexWhere((r) => r.id == repositoryId);
    if (from < 0 || to < 0 || to >= repos.length || from == to) return repos;
    final next = [...repos];
    next.insert(to, next.removeAt(from));
    return next;
  });

  /// Applies [change] to the current list, shows it at once, then keeps it on the device.
  Future<void> _update(List<ScraperRepo> Function(List<ScraperRepo> repos) change) async {
    final next = change(state.value ?? await future);
    state = AsyncData(next);
    final userId = ref.read(sessionProvider).user?.id;
    if (userId == null) return;
    try {
      await ref.read(localStoreProvider).write(keyFor(userId), next.isEmpty ? null : ScraperRepo.encodeList(next));
    } catch (_) {
      // Not kept (private browsing…): the choices last until the app is closed.
    }
  }
}

/// Downloads manifests and scrapers' code. The code is kept in memory until the app closes; it is
/// never written to the device and never run here (that is the runtime's job).
class ScraperLoader {
  ScraperLoader(this._http);

  final ScraperHttp _http;
  final _code = <String, String>{};

  Future<RepositoryManifest> manifest(String url) async {
    final text = await _download(url);
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const ScraperException("Ce n'est pas le manifeste d'un dépôt de plug-ins.");
    }
    return RepositoryManifest.parse(json, fallbackName: ScraperRepo.hostOf(url));
  }

  Future<String> code(ScraperRepo repo, ScraperInfo scraper) async {
    final url = repo.fileOf(scraper).toString();
    return _code[url] ??= await _download(url);
  }

  void forgetCode() => _code.clear();

  Future<String> _download(String url) async {
    final refused = ScraperGuard.check(url);
    if (refused != null) throw ScraperException('Adresse refusée : $refused.');
    final ScraperHttpResponse response;
    try {
      response = await _http.send(ScraperHttpRequest(url: url));
    } on ScraperException {
      rethrow;
    } on ApiException catch (e) {
      throw ScraperException(e.message);
    } catch (_) {
      throw const ScraperException('Téléchargement impossible. Vérifiez la connexion et l’adresse.');
    }
    if (response.status < 200 || response.status >= 300) {
      throw ScraperException('Téléchargement impossible (erreur ${response.status}).');
    }
    return response.body;
  }
}

/// Asks a scraper for the streams of a title.
class ScraperService {
  ScraperService(this._ref);

  final Ref _ref;

  /// At most this many scrapers run at once: the sources panel asks them all together and a phone
  /// should not start thirty JavaScript engines.
  static const maxParallel = 3;

  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<List<ScraperStream>> streams(ScraperRepo repo, ScraperInfo scraper, PlaybackItem item) async {
    final isMovie = item.type == MediaType.movie;
    final params = ScraperParams(
      tmdbId: '${item.id}',
      mediaType: isMovie ? 'movie' : 'tv',
      season: isMovie ? null : item.season,
      episode: isMovie ? null : item.episode,
    );
    if (repo.mode == ScraperMode.server) return _onServer(repo, scraper, params, item.id);

    await _acquire();
    try {
      final code = await _ref.read(scraperLoaderProvider).code(repo, scraper);
      return await _ref
          .read(scraperRuntimeProvider)
          .run(code: code, params: params, fetch: _ref.read(scraperHttpProvider).send);
    } finally {
      _release();
    }
  }

  Future<List<ScraperStream>> _onServer(ScraperRepo repo, ScraperInfo scraper, ScraperParams params, int id) async {
    try {
      final json = await _ref
          .read(apiClientProvider)
          .post(
            '/scrapers/run',
            body: {
              'repository_url': repo.url,
              'scraper_id': scraper.id,
              'tmdb_id': id,
              'media_type': params.mediaType,
              'season': params.season,
              'episode': params.episode,
            },
            // The server may wait for the scraper up to a minute.
            receiveTimeout: const Duration(seconds: 65),
          );
      return ScraperStream.parseList(json['data']);
    } on ApiException catch (e) {
      throw ScraperException(e.message);
    }
  }

  Future<void> _acquire() async {
    if (_running < maxParallel) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future; // the slot is handed over: the count stays
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }
}

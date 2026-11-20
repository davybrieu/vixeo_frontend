/// Plug-ins: repositories of JavaScript scrapers, façon Nuvio (`docs/scrapers.md`).
///
/// This file is the app's logic for them, in four parts:
/// - [ScraperRepos]: the installed repositories, kept **on the device**
///   (`LocalStore`), per account, in the person's order, each on or off.
/// - [ScraperLoader]: downloads manifests and scrapers' code (never run here).
/// - [ScraperService]: asks one scraper for the streams of a title, on the device.
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
final scraperHttpProvider = Provider<ScraperHttp>((ref) => createScraperHttp());

/// Where scrapers' JavaScript runs on this platform (tests replace it).
final scraperRuntimeProvider = Provider<ScraperRuntime>((ref) => createLocalScraperRuntime());

final scraperLoaderProvider = Provider<ScraperLoader>((ref) => ScraperLoader(ref.read(scraperHttpProvider)));

final scraperServiceProvider = Provider<ScraperService>((ref) => ScraperService(ref));

/// What the scrapers did on this device: the « Journal » of the sources panel (appui long sur une
/// source).
final scraperJournalProvider = Provider<ScraperJournal>((ref) => ScraperJournal());

/// The last run of each source: its requests (address, status or why it failed, time, size), what
/// the scraper wrote in its console, how the run ended. In memory only. Made to find out, on a
/// phone, why a source finds nothing (demande du développeur, 20/11/2026).
class ScraperJournal {
  static const maxLines = 400;
  static const maxLineLength = 300;

  final _runs = <String, List<String>>{};

  /// The lines of the last run of [provider] (`scraper:…`); none when it has not run yet.
  List<String> of(String provider) => List.unmodifiable(_runs[provider] ?? const <String>[]);

  /// Starts the journal of a new run of [provider] (the previous one is dropped) and returns what
  /// writes a line in it, after the seconds since the start.
  void Function(String line) start(String provider) {
    final lines = <String>[];
    _runs[provider] = lines;
    final clock = Stopwatch()..start();
    return (line) {
      if (lines.length > maxLines) return;
      if (lines.length == maxLines) {
        lines.add('… (journal coupé)');
        return;
      }
      final text = line.length > maxLineLength ? '${line.substring(0, maxLineLength)}…' : line;
      lines.add('${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(5)} s  $text');
    };
  }
}

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

  Future<String> _download(String address) async {
    final url = ScraperGuard.upgrade(address);
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
  /// should not start thirty JavaScript engines. Nuvio runs up to ten; a repository like
  /// gowaru-nuvio-providers has some thirty scrapers that mostly wait for the network, a Vixeo
  /// TV box has little memory: six is the middle.
  static const maxParallel = 6;

  int _running = 0;
  final _waiting = <Completer<void>>[];

  /// The streams [scraper] finds for [item]. [journal] gets a line for each step, request and
  /// console message (see [ScraperJournal]).
  Future<List<ScraperStream>> streams(
    ScraperRepo repo,
    ScraperInfo scraper,
    PlaybackItem item, {
    void Function(String line)? journal,
  }) async {
    final note = journal ?? (String _) {};
    final isMovie = item.type == MediaType.movie;
    final params = ScraperParams(
      tmdbId: '${item.id}',
      mediaType: isMovie ? 'movie' : 'tv',
      season: isMovie ? null : item.season,
      episode: isMovie ? null : item.episode,
      // Nuvio's SCRAPER_ID: the manifest's address (lower case) and the scraper's id.
      scraperId: '${repo.url.toLowerCase()}:${scraper.id}',
    );
    note(
      '${scraper.name} (${scraper.id}) : ${params.mediaType} ${params.tmdbId}'
      '${isMovie ? '' : ' saison ${params.season} épisode ${params.episode}'}',
    );
    await _acquire();
    try {
      note('démarrage');
      final code = await _ref.read(scraperLoaderProvider).code(repo, scraper);
      note('code : ${code.length} caractères');
      final http = _ref.read(scraperHttpProvider);
      final streams = await _ref
          .read(scraperRuntimeProvider)
          .run(
            code: code,
            params: params,
            fetch: (request) async {
              final clock = Stopwatch()..start();
              try {
                final response = await http.send(request);
                note(
                  '${request.method} ${request.url} → ${response.status} '
                  '(${clock.elapsedMilliseconds} ms, ${response.body.length} car.)',
                );
                return response;
              } catch (error) {
                note('${request.method} ${request.url} → échec : ${_reason(error)} (${clock.elapsedMilliseconds} ms)');
                rethrow;
              }
            },
            onLog: (level, message) => note('[$level] $message'),
          );
      note('fin : ${streams.length} flux');
      return streams;
    } catch (error) {
      note('erreur : ${_reason(error)}');
      rethrow;
    } finally {
      _release();
    }
  }

  static String _reason(Object error) => switch (error) {
    ScraperException(:final message) => message,
    ApiException(:final message) => message,
    _ => '$error',
  };

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

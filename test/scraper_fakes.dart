/// Stand-ins for the plug-in system's outside world (network, JavaScript engine, account), shared
/// by the plug-in tests: `scraper_models_test.dart`, `scraper_runner_test.dart`, `addons_test.dart`
/// and `playback_test.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/local_store.dart';
import 'package:vixeo/features/addons/scraper_guard.dart';
import 'package:vixeo/features/addons/scraper_host.dart';
import 'package:vixeo/features/addons/scraper_http.dart';
import 'package:vixeo/features/addons/scraper_models.dart';
import 'package:vixeo/features/addons/scraper_runtime.dart';
import 'package:vixeo/features/addons/scrapers.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';

const repoUrl = 'https://repo.test/manifest.json';

/// A repository with a movie scraper, a series scraper and one for both.
Map<String, Object?> manifestJson() => {
  'name': 'Dépôt test',
  'version': '1.0.0',
  'scrapers': [
    {
      'id': 'films',
      'name': 'Films libres',
      'filename': 'providers/films.js',
      'version': '1.2.0',
      'description': 'Des films.',
      'supportedTypes': ['movie'],
    },
    {
      'id': 'series',
      'name': 'Séries libres',
      'filename': 'providers/series.js',
      'supportedTypes': ['tv'],
    },
    {'id': 'tout', 'name': 'Tout', 'filename': 'https://cdn.test/tout.js'},
  ],
};

/// The repository of [manifestJson], as installed.
ScraperRepo testRepo() =>
    ScraperRepo.fromManifest(repoUrl, RepositoryManifest.parse(manifestJson(), fallbackName: 'repo.test'));

/// A signed-in account (the plug-ins are kept per account).
class SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    user: User(id: 7, name: 'Test', email: 'test@vixeo.test', parentalControl: false),
  );
}

/// Serves files from a map; anything else is a 404.
class FakeScraperHttp implements ScraperHttp {
  FakeScraperHttp(this.files);

  final Map<String, String> files;
  final requests = <ScraperHttpRequest>[];

  @override
  Future<ScraperHttpResponse> send(ScraperHttpRequest request) async {
    requests.add(request);
    final body = files[request.url];
    return body == null
        ? ScraperHttpResponse(status: 404, url: request.url)
        : ScraperHttpResponse(status: 200, body: body, url: request.url);
  }
}

/// Runs no JavaScript: answers with [answer], and keeps what it was asked.
class FakeScraperRuntime implements ScraperRuntime {
  final calls = <({String code, ScraperParams params})>[];
  Object? error;
  List<ScraperStream> Function(String code, ScraperParams params) answer = (_, _) => const [];

  @override
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  }) async {
    calls.add((code: code, params: params));
    if (error != null) throw error!;
    return answer(code, params);
  }
}

/// An account with the repository of [manifestJson] installed (or [repos]), and no outside world.
ProviderContainer scraperContainer({
  List<ScraperRepo>? repos,
  FakeScraperHttp? http,
  FakeScraperRuntime? runtime,
  MemoryLocalStore? store,
  ApiClient? api,
  List<Override> extraOverrides = const [],
}) {
  final localStore = store ?? MemoryLocalStore();
  if (repos != null) localStore.values[ScraperRepos.keyFor(7)] = ScraperRepo.encodeList(repos);
  return ProviderContainer(
    // Like the app (`main.dart`): a failed request is an error, not retried in the background.
    retry: (_, _) => null,
    overrides: [
      sessionProvider.overrideWith(SignedIn.new),
      localStoreProvider.overrideWithValue(localStore),
      scraperHttpProvider.overrideWithValue(http ?? FakeScraperHttp({})),
      scraperRuntimeProvider.overrideWithValue(runtime ?? FakeScraperRuntime()),
      if (api != null) apiClientProvider.overrideWithValue(api),
      ...extraOverrides,
    ],
  );
}

/// Android / iOS (and the tests): scrapers run in QuickJS, in an isolate that can be killed.
library;

import 'scraper_guard.dart';
import 'scraper_host.dart';
import 'scraper_js_engine_io.dart';
import 'scraper_models.dart';
import 'scraper_runtime.dart';

class IsolateScraperRuntime implements ScraperRuntime {
  /// [startEngine] is replaced in the tests by a fake engine.
  IsolateScraperRuntime({Future<JsEngine> Function()? startEngine})
    : _startEngine = startEngine ?? IsolateJsEngine.start;

  final Future<JsEngine> Function() _startEngine;

  @override
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  }) async {
    final prelude = await loadSandboxPrelude();
    final JsEngine engine;
    try {
      engine = await _startEngine();
    } catch (_) {
      throw const ScraperException("Le moteur des plug-ins n'a pas pu démarrer sur cet appareil.");
    }
    return ScraperRunner.run(
      engine: engine,
      prelude: prelude,
      code: code,
      params: params,
      fetch: fetch,
      limits: limits,
      onLog: onLog,
    );
  }
}

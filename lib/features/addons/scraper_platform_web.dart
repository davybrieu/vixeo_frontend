/// Flutter Web cannot run the native flutter_js engine (it depends on dart:ffi).
///
/// Plug-in scraper execution is therefore unavailable on Web. The rest of Vixeo remains
/// available, and native platforms continue to use QuickJS / JavaScriptCore.
library;

import 'scraper_http.dart';
import 'scraper_models.dart';
import 'scraper_runtime.dart';

ScraperRuntime createLocalScraperRuntime() => _UnsupportedWebScraperRuntime();

ScraperHttp createScraperHttp() => _UnsupportedWebScraperHttp();

class _UnsupportedWebScraperRuntime implements ScraperRuntime {
  @override
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  }) {
    throw const ScraperException(
      'Les plug-ins JavaScript ne sont pas disponibles sur la version Web.',
    );
  }
}

class _UnsupportedWebScraperHttp implements ScraperHttp {
  @override
  Future<ScraperHttpResponse> send(ScraperHttpRequest request) {
    throw const ScraperException(
      'Les requêtes des plug-ins ne sont pas disponibles sur la version Web.',
    );
  }
}

/// Runs a scraper's JavaScript. What differs from one platform to another is only the engine:
/// QuickJS in an isolate on Android / iOS ([scraper_runtime_io.dart]), a sandboxed iframe in the
/// browser ([scraper_runtime_web.dart]). The conversation with the sandbox is common
/// ([ScraperHost]).
library;

import 'package:flutter/services.dart' show rootBundle;

import 'scraper_guard.dart';
import 'scraper_host.dart';
import 'scraper_models.dart';

abstract class ScraperRuntime {
  /// Runs [code] (a scraper) for [params] and returns its streams. Every request it makes goes
  /// through [fetch], after the guard. Throws a [ScraperException].
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  });
}

Future<String>? _prelude;

/// The sandbox's prelude (`assets/scrapers/sandbox.js`), read once.
Future<String> loadSandboxPrelude() => _prelude ??= rootBundle.loadString('assets/scrapers/sandbox.js');

Future<String>? _cryptoJs;

/// crypto-js 4.2.0 (`assets/scrapers/crypto-js.min.js`, MIT), which Nuvio lends to its plug-ins as
/// the global `CryptoJS` and as `require('crypto-js')`. Read once.
Future<String> loadCryptoJs() => _cryptoJs ??= rootBundle.loadString('assets/scrapers/crypto-js.min.js');

final _cryptoJsUse = RegExp(r'''\bCryptoJS\b|['"]crypto-js['"]''');

/// Whether [code] uses CryptoJS (the same rule as `usesCryptoJs` in `tools/scraper-runner`).
bool usesCryptoJs(String code) => _cryptoJsUse.hasMatch(code);

/// The libraries the sandbox runs before [code]: CryptoJS for a scraper that names it, nothing
/// otherwise (62 KB a scraper does not need is not parsed for nothing).
Future<List<String>> librariesFor(String code) async => usesCryptoJs(code) ? [await loadCryptoJs()] : const [];

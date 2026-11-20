import 'scraper_http.dart';
import 'scraper_http_io.dart';
import 'scraper_runtime.dart';
import 'scraper_runtime_io.dart';

/// Android, Windows and the tests: QuickJS in an isolate (iOS: JavaScriptCore).
ScraperRuntime createLocalScraperRuntime() => IsolateScraperRuntime();

/// The device makes the requests itself.
ScraperHttp createScraperHttp() => DirectScraperHttp();

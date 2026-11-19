import '../../core/api/api_client.dart';
import 'scraper_http.dart';
import 'scraper_http_io.dart';
import 'scraper_runtime.dart';
import 'scraper_runtime_io.dart';

/// Android, iOS and the tests: QuickJS in an isolate.
ScraperRuntime createLocalScraperRuntime() => IsolateScraperRuntime();

/// Android, iOS and the tests: the device makes the requests itself.
ScraperHttp createScraperHttp(ApiClient api) => DirectScraperHttp();

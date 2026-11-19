import '../../core/api/api_client.dart';
import 'scraper_http.dart';
import 'scraper_runtime.dart';
import 'scraper_runtime_web.dart';

/// The browser: a sandboxed iframe.
ScraperRuntime createLocalScraperRuntime() => WebScraperRuntime();

/// The browser cannot read most sites (CORS): the Vixeo server makes the requests.
ScraperHttp createScraperHttp(ApiClient api) => ProxyScraperHttp(api);

/// Picks what the platform the app was compiled for needs (`createLocalScraperRuntime`,
/// `createScraperHttp`).
///
/// A "conditional import", like `playback/engine/engine_factory.dart`: the compiler keeps one of
/// the two files. A web build has no `dart:io` and never reads `flutter_js`; Android, iOS and the
/// tests take the `_io` file.
library;

export 'scraper_platform_io.dart' if (dart.library.js_interop) 'scraper_platform_web.dart';

/// Platform-specific plug-in scraper implementations.
///
/// Native platforms use QuickJS / JavaScriptCore. Flutter Web deliberately selects the
/// unsupported implementation: flutter_js depends on dart:ffi and cannot be compiled to JS.
library;

export 'scraper_platform_io.dart'
    if (dart.library.js_interop) 'scraper_platform_web.dart';

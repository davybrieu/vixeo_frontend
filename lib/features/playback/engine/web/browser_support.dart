/// What the browser can do (HLS on its own, Media Source Extensions, autoplay), asked to the
/// browser itself on the web. Elsewhere there is no browser: neutral answers.
library;

export 'browser_support_stub.dart' if (dart.library.js_interop) 'browser_support_web.dart';

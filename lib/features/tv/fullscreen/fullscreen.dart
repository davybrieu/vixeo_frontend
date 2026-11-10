/// Full screen for the live player: the browser's full screen on the web, immersive mode (no
/// system bars) and landscape on Android / iOS.
library;

export 'fullscreen_io.dart' if (dart.library.js_interop) 'fullscreen_web.dart';

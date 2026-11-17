/// The player's screen: always horizontal while it is open (`lockLandscape`), and full screen on
/// demand: the browser's full screen on the web, immersive mode (no system bars) on Android / iOS.
library;

export 'fullscreen_io.dart' if (dart.library.js_interop) 'fullscreen_web.dart';

/// hls.js, seen from Dart: only what the player uses.
///
/// `web/hls.min.js` (hls.js, Apache-2.0, served from our own origin) is **not** loaded by
/// `index.html`: [ensureHlsJsLoaded] adds its `<script>` the first time a stream needs it, so a
/// browser that plays HLS on its own (Safari) never downloads it.
@JS()
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `window.Hls`: null until the script is loaded.
@JS('Hls')
external JSAny? get _hlsGlobal;

/// The `Hls` class of hls.js. An "extension type" is a Dart name put on a JavaScript object:
/// no wrapper at run time, just typed access to its methods.
extension type Hls._(JSObject _) implements JSObject {
  external factory Hls(JSObject config);

  external static bool isSupported();

  external void attachMedia(web.HTMLMediaElement media);
  external void loadSource(String url);
  external void on(String event, JSFunction handler);
  external void startLoad();
  external void recoverMediaError();
  external void destroy();
}

bool get hlsJsLoaded => _hlsGlobal != null;

Future<bool>? _loading;

/// Loads hls.js once, when a stream needs it. False when the script cannot be had.
Future<bool> ensureHlsJsLoaded() {
  if (hlsJsLoaded) return Future.value(true);
  return _loading ??= _load();
}

Future<bool> _load() {
  final done = Completer<bool>();
  void finish(bool ok) {
    // A failed download may be tried again with the next stream.
    if (!ok) _loading = null;
    if (!done.isCompleted) done.complete(ok);
  }

  final script = web.HTMLScriptElement()
    // Relative to <base href>: next to index.html, on our own origin.
    ..src = 'hls.min.js'
    ..async = true;
  script.addEventListener('load', ((web.Event _) => finish(hlsJsLoaded)).toJS);
  script.addEventListener('error', ((web.Event _) => finish(false)).toJS);
  final parent = web.document.head ?? web.document.body;
  if (parent == null) {
    finish(false);
  } else {
    parent.appendChild(script);
  }
  return done.future;
}

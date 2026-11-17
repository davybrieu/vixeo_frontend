/// What this browser can do, asked through the DOM (`package:web`, the typed bindings of the
/// browser's JavaScript API: the Dart counterpart of writing `document.createElement('video')`).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether `<video>` plays HLS without any library (Safari, iOS, recent Chrome…): the browser
/// answers "maybe" or "probably", or an empty string when it does not.
bool browserPlaysHlsNatively() {
  try {
    final video = web.document.createElement('video') as web.HTMLVideoElement;
    return video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Whether hls.js can run: it needs Media Source Extensions (`MediaSource`, or
/// `ManagedMediaSource` on iPhone since iOS 17.1). Asked without loading hls.js.
bool browserHasMediaSource() {
  try {
    return globalContext.has('MediaSource') || globalContext.has('ManagedMediaSource');
  } catch (_) {
    return false;
  }
}

/// Whether the viewer already clicked, tapped or pressed a key on this page
/// (`navigator.userActivation.hasBeenActive`). Before that, browsers only let a video start
/// muted. A browser too old to say is taken at its word: a refused start is handled anyway.
bool viewerHasInteracted() {
  try {
    final navigator = globalContext['navigator'];
    if (navigator == null) return true;
    final activation = (navigator as JSObject)['userActivation'];
    if (activation == null) return true;
    final active = (activation as JSObject)['hasBeenActive'];
    if (active == null || !active.typeofEquals('boolean')) return true;
    return (active as JSBoolean).toDart;
  } catch (_) {
    return true;
  }
}

/// After a request the page could not read: asks again without wanting to read the answer
/// (`no-cors`). An answer then means the server is there and only refuses this website (CORS);
/// no answer means the network (or the server) is down. The download is cancelled at once.
Future<bool> looksLikeCorsRefusal(String url) async {
  try {
    final abort = web.AbortController();
    await web.window.fetch(url.toJS, web.RequestInit(mode: 'no-cors', cache: 'no-store', signal: abort.signal)).toDart;
    abort.abort();
    return true;
  } catch (_) {
    return false;
  }
}

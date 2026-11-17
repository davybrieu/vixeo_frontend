import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool _landscapeLocked = false;

/// Whether the page is full screen (Échap can leave it without the app knowing: always asked).
bool isFullscreen() => web.document.fullscreenElement != null;

/// The player is always horizontal. A browser only lets a page lock the orientation while it is
/// full screen (Chrome, Edge and Firefox on Android; never Safari on iPhone, nor a computer): the
/// lock is asked now, and again when the page goes full screen. Refused: the page turns with the
/// phone, as any web page.
Future<void> lockLandscape() async {
  _landscapeLocked = true;
  await _lock();
}

Future<void> unlockOrientation() async {
  _landscapeLocked = false;
  try {
    web.window.screen.orientation.unlock();
  } catch (_) {}
}

Future<void> enterFullscreen() async {
  if (isFullscreen()) return;
  try {
    await web.document.documentElement?.requestFullscreen().toDart;
  } catch (_) {
    // Refused by the browser (no user gesture, iframe…): the player stays in the page.
    return;
  }
  if (_landscapeLocked) await _lock();
}

Future<void> exitFullscreen() async {
  if (!isFullscreen()) return;
  try {
    await web.document.exitFullscreen().toDart;
  } catch (_) {}
}

Future<void> _lock() async {
  try {
    await web.window.screen.orientation.lock('landscape').toDart;
  } catch (_) {
    // Not full screen, a computer, or Safari: nothing to lock.
  }
}

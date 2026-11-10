import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Whether the page is full screen (Échap can leave it without the app knowing: always asked).
bool isFullscreen() => web.document.fullscreenElement != null;

Future<void> enterFullscreen() async {
  if (isFullscreen()) return;
  try {
    await web.document.documentElement?.requestFullscreen().toDart;
  } catch (_) {
    // Refused by the browser (no user gesture, iframe…): the player stays in the page.
  }
}

Future<void> exitFullscreen() async {
  if (!isFullscreen()) return;
  try {
    await web.document.exitFullscreen().toDart;
  } catch (_) {}
}

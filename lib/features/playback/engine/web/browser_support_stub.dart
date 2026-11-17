/// Not a browser: nothing to ask (see `browser_support_web.dart`).
library;

bool browserPlaysHlsNatively() => false;

bool browserHasMediaSource() => false;

/// No autoplay policy outside a browser.
bool viewerHasInteracted() => true;

Future<bool> looksLikeCorsRefusal(String url) async => false;

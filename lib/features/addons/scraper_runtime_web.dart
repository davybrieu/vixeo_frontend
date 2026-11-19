/// The browser: a scraper runs in a hidden **sandboxed iframe**.
///
/// `sandbox="allow-scripts"` (and not `allow-same-origin`) gives the frame an empty origin: it cannot
/// read the app's page, cookies, storage or token. Its own content-security policy
/// (`default-src 'none'`) forbids every network access: not `fetch`, not a `WebSocket`, not an
/// `<img>`. Its only door is `postMessage` to the app, which answers `fetch` messages through the
/// Vixeo server ([ProxyScraperHttp]) after the guard, exactly as for the QuickJS engine.
///
/// For a Vue developer: an `<iframe sandbox>` is the closest thing to a Web Worker you can lock
/// down from outside.
///
/// Not verified in a browser yet (`docs/scrapers.md` §9).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'scraper_guard.dart';
import 'scraper_host.dart';
import 'scraper_models.dart';
import 'scraper_runtime.dart';

class WebScraperRuntime implements ScraperRuntime {
  @override
  Future<List<ScraperStream>> run({
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    ScraperLog? onLog,
    ScraperLimits limits = ScraperLimits.standard,
  }) async {
    final prelude = await loadSandboxPrelude();
    final nonce = _nonce();
    final ready = Completer<void>();
    final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
    iframe
      ..setAttribute('sandbox', 'allow-scripts')
      ..setAttribute('aria-hidden', 'true')
      ..style.display = 'none'
      ..srcdoc = sandboxPage(prelude, nonce);

    void post(Map<String, Object?> message) {
      iframe.contentWindow?.postMessage({'nonce': nonce, ...message}.jsify()!, '*'.toJS);
    }

    final host = ScraperHost(fetch: fetch, limits: limits, onLog: onLog, send: (reply) => post(reply.toMessage()));
    final listener = ((web.MessageEvent event) {
      // Only messages that carry this run's secret: the page has other windows and extensions.
      final data = event.data.dartify();
      if (data is! Map || data['nonce'] != nonce) return;
      final message = data['m'];
      if (message is Map && message['t'] == 'ready') {
        if (!ready.isCompleted) ready.complete();
      } else {
        host.handle(message);
      }
    }).toJS;

    web.window.addEventListener('message', listener);
    web.document.body!.append(iframe);
    try {
      await ready.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw const ScraperException("Le moteur des plug-ins n'a pas pu démarrer."),
      );
      post({'op': 'run', 'code': code, 'params': params.toJson()});
      return await host.result.timeout(
        limits.run,
        onTimeout: () => throw const ScraperException('Le plug-in a mis trop de temps à répondre.'),
      );
    } finally {
      host.close();
      web.window.removeEventListener('message', listener);
      iframe.remove();
    }
  }

  static String _nonce() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }
}

/// The page of the iframe: the prelude, then the glue that turns `postMessage` into the host
/// protocol of `sandbox.js`. Only the parent window's messages that carry [nonce] are obeyed.
String sandboxPage(String prelude, String nonce) =>
    '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'">
</head><body><script>$prelude</script><script>
(function () {
  var nonce = ${jsonEncode(nonce)};
  __vx.emit = function (m) { parent.postMessage({ nonce: nonce, m: m }, '*'); };
  addEventListener('message', function (e) {
    var d = e.data;
    if (!d || d.nonce !== nonce || e.source !== parent) return;
    if (d.op === 'run') __vx.run(d.code, d.params);
    else if (d.op === 'deliver') __vx.deliver(d.id, d.res);
    else if (d.op === 'timer') __vx.timer(d.id);
  });
  parent.postMessage({ nonce: nonce, m: { t: 'ready' } }, '*');
})();
</script></body></html>''';

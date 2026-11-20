import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/features/addons/scraper_guard.dart';
import 'package:vixeo/features/addons/scraper_host.dart';
import 'package:vixeo/features/addons/scraper_http.dart';
import 'package:vixeo/features/addons/scraper_http_io.dart';
import 'package:vixeo/features/addons/scraper_models.dart';

/// A JavaScript engine that runs nothing: it plays the sandbox's part from a script. The real
/// sandbox is tested against QuickJS in `tools/scraper-runner` (`npm test`); here only the
/// conversation of [ScraperRunner] and [ScraperHost] is.
class ScriptedEngine implements JsEngine {
  ScriptedEngine({this.onRun, this.onReply});

  /// Called when the scraper is started: queues the sandbox's first messages.
  final void Function(ScriptedEngine engine)? onRun;

  /// Called with each answer the host sends in (`__vx.deliver(…)`, `__vx.timer(…)`).
  final void Function(ScriptedEngine engine, String source)? onReply;

  final outbox = <Map<String, Object?>>[];
  final evaluated = <String>[];
  final delivered = <String>[];
  bool disposed = false;

  @override
  Future<String> evaluate(String source) async {
    evaluated.add(source);
    if (source == '__vx.take()') {
      final out = jsonEncode(outbox);
      outbox.clear();
      return out;
    }
    if (source.startsWith('__vx.run(')) {
      onRun?.call(this);
    } else if (source.startsWith('__vx.deliver(') || source.startsWith('__vx.timer(')) {
      delivered.add(source);
      onReply?.call(this, source);
    }
    return '';
  }

  @override
  Future<void> runPendingJobs() async {}

  @override
  Future<void> dispose() async => disposed = true;

  void done(List<Object?> streams) => outbox.add({'t': 'done', 'ok': true, 'streams': streams});

  void fetch(int id, String url, {String method = 'GET', Object? body}) =>
      outbox.add({'t': 'fetch', 'id': id, 'url': url, 'method': method, 'headers': {'Accept': 'x'}, 'body': body});
}

const _params = ScraperParams(tmdbId: '550', mediaType: 'movie');

Future<List<ScraperStream>> run(
  ScriptedEngine engine, {
  ScraperFetch? fetch,
  ScraperLimits limits = ScraperLimits.standard,
  ScraperLog? onLog,
  String code = 'module.exports = {};',
  List<String> libraries = const [],
}) => ScraperRunner.run(
  engine: engine,
  prelude: '/* prelude */',
  code: code,
  params: _params,
  fetch: fetch ?? (request) async => ScraperHttpResponse(status: 200, url: request.url),
  libraries: libraries,
  limits: limits,
  onLog: onLog,
);

void main() {
  test('a name the network resolves to a local address is refused, and the address is said', () async {
    final http = DirectScraperHttp(lookup: (_) async => [InternetAddress('127.0.0.1')]);
    await expectLater(
      http.send(const ScraperHttpRequest(url: 'https://blocked.example.org/api')),
      throwsA(
        isA<ScraperException>().having(
          (e) => e.message,
          'message',
          'adresse privée interdite (blocked.example.org → 127.0.0.1)',
        ),
      ),
    );
  });

  test('reads a body in the charset of its Content-Type, UTF-8 by default (as Nuvio)', () {
    expect(decodeScraperBody(utf8.encode('Odyssée'), 'text/html; charset=UTF-8'), 'Odyssée');
    expect(decodeScraperBody(utf8.encode('Odyssée'), null), 'Odyssée');
    expect(decodeScraperBody(latin1.encode('Odyssée'), 'text/html; charset="ISO-8859-1"'), 'Odyssée');
    expect(decodeScraperBody(latin1.encode('Odyssée'), 'text/html;charset=windows-1252'), 'Odyssée');
  });

  test('never asks flutter_js for a memory limit: its QuickJS for Android lacks it, every scraper then failed', () {
    final source = File('lib/features/addons/scraper_js_engine_io.dart').readAsStringSync();
    expect(source, isNot(contains('memoryLimit:')));
    expect(source, contains('QuickJsRuntime2(stackSize: 1024 * 1024)'));
  });

  group('ScraperRunner', () {
    test('loads the prelude, starts the scraper with its parameters, and returns its streams', () async {
      final engine = ScriptedEngine(
        onRun: (e) => e.done([
          {'url': 'https://cdn.test/a.m3u8', 'name': 'A', 'quality': '1080p'},
          {'url': 'javascript:alert(1)'},
        ]),
      );

      final streams = await run(engine, code: 'module.exports = { getStreams() {} };');

      expect(streams.map((s) => s.url), ['https://cdn.test/a.m3u8']);
      expect(streams.single.quality, '1080p');
      expect(engine.evaluated.first, '/* prelude */');
      final start = engine.evaluated[1];
      expect(start, startsWith('__vx.run('));
      expect(start, contains(jsonEncode('module.exports = { getStreams() {} };')));
      expect(start, contains('"tmdbId":"550"'));
      expect(start, contains('"mediaType":"movie"'));
      // Nuvio's SCRAPER_SETTINGS (always the defaults), and no library lent.
      expect(start, contains('"settings":{}'));
      expect(start, endsWith(', [])'));
      expect(engine.disposed, isTrue);
    });

    test('lends the libraries it is given to the sandbox, before the scraper', () async {
      final engine = ScriptedEngine(onRun: (e) => e.done(const []));

      await run(engine, libraries: const ['var CryptoJS = {};']);

      expect(engine.evaluated[1], endsWith(', ${jsonEncode(['var CryptoJS = {};'])})'));
    });

    test('makes a request in http:// in https://, as the guard wants', () async {
      final asked = <String>[];
      final engine = ScriptedEngine(
        onRun: (e) => e.fetch(1, 'http://api.test/x?y=1'),
        onReply: (e, source) => e.done(const []),
      );

      await run(
        engine,
        fetch: (request) async {
          asked.add(request.url);
          return ScraperHttpResponse(status: 200, url: request.url);
        },
      );

      expect(asked, ['https://api.test/x?y=1']);
      expect(engine.delivered.single, contains('"status":200'));
    });

    test('does a request for the scraper, and gives the answer back to it', () async {
      final asked = <ScraperHttpRequest>[];
      final engine = ScriptedEngine(
        onRun: (e) => e.fetch(1, 'https://api.test/find?id=550'),
        onReply: (e, source) => e.done([
          {'url': 'https://cdn.test/a.mp4'},
        ]),
      );

      final streams = await run(
        engine,
        fetch: (request) async {
          asked.add(request);
          return ScraperHttpResponse(status: 200, statusText: 'OK', body: '{"ok":true}', url: request.url);
        },
      );

      expect(streams.single.streamType, 'mp4');
      expect(asked.single.url, 'https://api.test/find?id=550');
      expect(asked.single.method, 'GET');
      expect(asked.single.headers, {'accept': 'x'});
      expect(engine.delivered.single, startsWith('__vx.deliver(1, '));
      expect(engine.delivered.single, contains(r'"body":"{\"ok\":true}"'));
      expect(engine.delivered.single, contains('"status":200'));
    });

    test('refuses a request the guard refuses, without making it, and tells the scraper why', () async {
      var made = 0;
      final engine = ScriptedEngine(
        onRun: (e) => e.fetch(1, 'https://127.0.0.1/admin'),
        onReply: (e, source) => e.done(const []),
      );

      final streams = await run(
        engine,
        fetch: (request) async {
          made++;
          return ScraperHttpResponse(status: 200, url: request.url);
        },
      );

      expect(streams, isEmpty);
      expect(made, 0);
      expect(engine.delivered.single, contains('adresse privée interdite'));
    });

    test('refuses the requests after the limit, and a body that is too big', () async {
      var made = 0;
      var answers = 0;
      final engine = ScriptedEngine(
        onRun: (e) {
          e.fetch(1, 'https://api.test/1');
          e.fetch(2, 'https://api.test/2');
          e.fetch(3, 'https://api.test/3');
          e.fetch(4, 'https://api.test/4');
        },
        onReply: (e, source) {
          if (++answers == 4) e.done(const []);
        },
      );

      await run(
        engine,
        limits: const ScraperLimits(requests: 3),
        fetch: (request) async {
          made++;
          return ScraperHttpResponse(status: 200, url: request.url);
        },
      );

      // The fourth is over the limit of three requests.
      expect(made, 3);
      expect(engine.delivered.where((d) => d.contains('trop de requêtes')), hasLength(1));
    });

    test('refuses a body that is too big', () async {
      var made = 0;
      final engine = ScriptedEngine(
        onRun: (e) => e.fetch(1, 'https://api.test/post', method: 'POST', body: 'x' * 11),
        onReply: (e, source) => e.done(const []),
      );

      await run(
        engine,
        limits: const ScraperLimits(requestBody: 10),
        fetch: (request) async {
          made++;
          return ScraperHttpResponse(status: 200, url: request.url);
        },
      );

      expect(made, 0);
      expect(engine.delivered.single, contains('corps trop gros'));
    });

    test('tells the scraper that a request failed, or took too long', () async {
      final engine = ScriptedEngine(
        onRun: (e) {
          e.fetch(1, 'https://api.test/down');
          e.fetch(2, 'https://api.test/slow');
          e.fetch(3, 'https://api.test/refused');
        },
        onReply: (e, source) {
          if (e.delivered.length == 3) e.done(const []);
        },
      );

      await run(
        engine,
        limits: const ScraperLimits(request: Duration(milliseconds: 30)),
        fetch: (request) {
          if (request.url.endsWith('/slow')) return Completer<ScraperHttpResponse>().future;
          if (request.url.endsWith('/refused')) return Future.error(const ScraperException('hôte introuvable'));
          return Future.error(StateError('network'));
        },
      );

      final all = engine.delivered.join('\n');
      expect(all, contains('requête impossible'));
      expect(all, contains('délai dépassé'));
      expect(all, contains('hôte introuvable'));
    });

    test('runs a timer the scraper asked for', () async {
      final engine = ScriptedEngine(
        onRun: (e) => e.outbox.add({'t': 'timer', 'id': 7, 'ms': 10}),
        onReply: (e, source) => e.done(const []),
      );

      await run(engine);

      expect(engine.delivered.single, '__vx.timer(7)');
    });

    test('stops a scraper that waits for nothing', () async {
      final engine = ScriptedEngine();

      await expectLater(
        run(engine),
        throwsA(isA<ScraperException>().having((e) => e.message, 'message', 'Le plug-in ne répond plus.')),
      );
      expect(engine.disposed, isTrue);
    });

    test('reports the error of a scraper that failed, with a default message', () async {
      final failing = ScriptedEngine(onRun: (e) => e.outbox.add({'t': 'done', 'ok': false, 'error': 'boom'}));
      await expectLater(run(failing), throwsA(isA<ScraperException>().having((e) => e.message, 'message', 'boom')));

      final silent = ScriptedEngine(onRun: (e) => e.outbox.add({'t': 'done', 'ok': false}));
      await expectLater(
        run(silent),
        throwsA(isA<ScraperException>().having((e) => e.message, 'message', 'Le plug-in a échoué.')),
      );
    });

    test('ends a run that lasts too long, and frees the engine', () async {
      final engine = ScriptedEngine(onRun: (e) => e.fetch(1, 'https://api.test/never'));

      await expectLater(
        run(
          engine,
          limits: const ScraperLimits(run: Duration(milliseconds: 50), request: Duration(milliseconds: 500)),
          fetch: (request) => Completer<ScraperHttpResponse>().future,
        ),
        throwsA(
          isA<ScraperException>().having((e) => e.message, 'message', 'Le plug-in a mis trop de temps à répondre.'),
        ),
      );
      expect(engine.disposed, isTrue);
    });

    test('passes the console on, and keeps the streams within the limit', () async {
      final logs = <String>[];
      final engine = ScriptedEngine(
        onRun: (e) {
          e.outbox.add({'t': 'log', 'level': 'warn', 'msg': 'hello'});
          e.done([for (var i = 0; i < 5; i++) {'url': 'https://cdn.test/$i'}]);
        },
      );

      final streams = await run(engine, limits: const ScraperLimits(streams: 2), onLog: (l, m) => logs.add('$l:$m'));

      expect(logs, ['warn:hello']);
      expect(streams.map((s) => s.url), ['https://cdn.test/0', 'https://cdn.test/1']);
    });
  });

  group('ScraperHost', () {
    test('ignores what it does not understand', () async {
      final replies = <ScraperReply>[];
      final host = ScraperHost(fetch: (_) async => throw StateError('never'), send: replies.add);

      host
        ..handle(null)
        ..handle('texte')
        ..handle({'t': 'inconnu'})
        ..handle({'t': 'fetch', 'id': 'pas un nombre'})
        ..handle({'t': 'timer'});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(replies, isEmpty);
      expect(host.pending, 0);
      expect(host.isDone, isFalse);
    });

    test('cuts a long timer to the limit', () async {
      final replies = <ScraperReply>[];
      final host = ScraperHost(
        fetch: (_) async => throw StateError('never'),
        send: replies.add,
        limits: const ScraperLimits(timer: Duration(milliseconds: 20)),
      );

      host.handle({'t': 'timer', 'id': 1, 'ms': 100000});
      expect(host.pending, 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(replies.single, isA<TimerReply>());
      expect(host.pending, 0);
    });

    test('says nothing once it is closed', () async {
      final replies = <ScraperReply>[];
      final host = ScraperHost(fetch: (r) async => ScraperHttpResponse(status: 200, url: r.url), send: replies.add);

      host.handle({'t': 'timer', 'id': 1, 'ms': 10});
      host.handle({'t': 'fetch', 'id': 2, 'url': 'https://api.test/x'});
      host.close();
      host.handle({'t': 'fetch', 'id': 3, 'url': 'https://api.test/y'});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(replies, isEmpty);
    });

    test('writes its answers as JavaScript and as messages', () {
      expect(const TimerReply(4).toJs(), '__vx.timer(4)');
      expect(const TimerReply(4).toMessage(), {'op': 'timer', 'id': 4});
      expect(const FetchReply(2, error: 'x').toJs(), '__vx.deliver(2, {"error":"x"})');
      expect(const FetchReply(2, error: 'x').toMessage(), {
        'op': 'deliver',
        'id': 2,
        'res': {'error': 'x'},
      });
      final reply = FetchReply(3, response: ScraperHttpResponse(status: 404, url: 'https://a.test/'));
      expect(reply.toMessage()['res'], containsPair('status', 404));
    });
  });
}

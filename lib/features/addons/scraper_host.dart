/// The app's side of the scraper sandbox (`assets/scrapers/sandbox.js`, `docs/scrapers.md`).
///
/// The sandbox sends **messages** (`fetch`, `timer`, `log`, `done`); the host answers them. This file
/// is that conversation, the same everywhere: [ScraperHost] checks and does what is asked, and
/// [ScraperRunner] feeds a JavaScript engine (QuickJS in an isolate) with the answers. In a browser
/// the engine is an iframe and `scraper_runtime_web.dart` carries the same messages with
/// `postMessage`. `tools/scraper-runner/host.mjs` is the same loop in JavaScript, tested against a
/// real QuickJS.
library;

import 'dart:async';
import 'dart:convert';

import 'scraper_guard.dart';
import 'scraper_http.dart';
import 'scraper_models.dart';

/// Does one (already checked) request. Usually a [ScraperHttp.send].
typedef ScraperFetch = Future<ScraperHttpResponse> Function(ScraperHttpRequest request);

typedef ScraperLog = void Function(String level, String message);

/// What the host sends back into the sandbox.
sealed class ScraperReply {
  const ScraperReply();

  /// JavaScript to evaluate in an engine.
  String toJs();

  /// The same, as a message for the iframe (`op`, `id` and the rest).
  Map<String, Object?> toMessage();
}

/// The answer to a `fetch`: the response, or [error] when the request could not be made.
class FetchReply extends ScraperReply {
  const FetchReply(this.id, {this.response, this.error});

  final int id;
  final ScraperHttpResponse? response;
  final String? error;

  Map<String, Object?> get _payload => response?.toJson() ?? {'error': error ?? 'erreur'};

  @override
  String toJs() => '__vx.deliver($id, ${jsonEncode(_payload)})';

  @override
  Map<String, Object?> toMessage() => {'op': 'deliver', 'id': id, 'res': _payload};
}

/// A `setTimeout` that came due.
class TimerReply extends ScraperReply {
  const TimerReply(this.id);

  final int id;

  @override
  String toJs() => '__vx.timer($id)';

  @override
  Map<String, Object?> toMessage() => {'op': 'timer', 'id': id};
}

/// Answers the sandbox's messages and collects its result.
///
/// [send] carries an answer back to the sandbox (the transport is the caller's). The host never
/// trusts a message: anything it does not understand is ignored, and every request goes through
/// [ScraperGuard] and the limits first.
class ScraperHost {
  ScraperHost({required this.fetch, required this.send, this.limits = ScraperLimits.standard, this.onLog});

  final ScraperFetch fetch;
  final void Function(ScraperReply reply) send;
  final ScraperLimits limits;
  final ScraperLog? onLog;

  final _result = Completer<List<ScraperStream>>();
  final _timers = <Timer>{};
  int _pending = 0;
  int _requests = 0;
  bool _closed = false;

  /// The scraper's streams, or its error (a [ScraperException]).
  Future<List<ScraperStream>> get result => _result.future;

  bool get isDone => _result.isCompleted;

  /// Answers still owed to the sandbox (requests in flight, timers running).
  int get pending => _pending;

  /// Handles one message of the sandbox.
  void handle(Object? message) {
    if (_closed || message is! Map) return;
    switch (message['t']) {
      case 'log':
        onLog?.call('${message['level']}', '${message['msg']}');
      case 'done':
        _finish(message);
      case 'timer':
        _timer(message);
      case 'fetch':
        _fetch(message);
    }
  }

  void _finish(Map<dynamic, dynamic> message) {
    if (isDone) return;
    if (message['ok'] == true) {
      _result.complete(ScraperStream.parseList(message['streams'], max: limits.streams));
    } else {
      final error = message['error'];
      _result.completeError(ScraperException(error is String && error.isNotEmpty ? error : 'Le plug-in a échoué.'));
    }
  }

  void _timer(Map<dynamic, dynamic> message) {
    final id = message['id'];
    if (id is! int) return;
    final asked = message['ms'] is num ? (message['ms'] as num).toInt() : 0;
    final ms = asked.clamp(0, limits.timer.inMilliseconds);
    _pending++;
    late final Timer timer;
    timer = Timer(Duration(milliseconds: ms), () {
      _timers.remove(timer);
      _answer(TimerReply(id));
    });
    _timers.add(timer);
  }

  void _fetch(Map<dynamic, dynamic> message) {
    final id = message['id'];
    if (id is! int) return;
    _pending++;
    final asked = ScraperHttpRequest.fromMessage(message);
    final request = asked.withUrl(ScraperGuard.upgrade(asked.url));
    final refused = ++_requests > limits.requests
        ? 'trop de requêtes'
        : (request.body != null && request.body!.length > limits.requestBody
              ? 'corps trop gros'
              : ScraperGuard.check(request.url));
    if (refused != null) {
      onLog?.call('garde', '${request.method} ${request.url} refusée : $refused');
      // Answered on the next turn, never inside the sandbox's own call.
      scheduleMicrotask(() => _answer(FetchReply(id, error: refused)));
      return;
    }
    fetch(request).timeout(limits.request).then<ScraperReply>(
      (response) => FetchReply(id, response: response),
      onError: (Object error) => FetchReply(id, error: _describe(error)),
    ).then(_answer);
  }

  static String _describe(Object error) {
    if (error is TimeoutException) return 'délai dépassé';
    if (error is ScraperException) return error.message;
    return 'requête impossible';
  }

  void _answer(ScraperReply reply) {
    _pending--;
    if (!_closed) send(reply);
  }

  /// Stops answering (the run is over, or was cancelled).
  void close() {
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// A JavaScript engine, possibly in another isolate. Every call may take a while, hence the futures.
abstract class JsEngine {
  /// Evaluates [source] and returns its result as text. Throws a [ScraperException] on an error.
  Future<String> evaluate(String source);

  /// Runs the promise callbacks that are waiting.
  Future<void> runPendingJobs();

  /// Frees the engine; one that is stuck in a loop is killed.
  Future<void> dispose();
}

/// Runs one scraper in a [JsEngine]: the sandbox's own prelude, then the scraper (after the
/// [libraries] lent to it, see `librariesFor`), then the conversation until it is done, or the
/// limits end it.
abstract final class ScraperRunner {
  static Future<List<ScraperStream>> run({
    required JsEngine engine,
    required String prelude,
    required String code,
    required ScraperParams params,
    required ScraperFetch fetch,
    List<String> libraries = const [],
    ScraperLimits limits = ScraperLimits.standard,
    ScraperLog? onLog,
  }) async {
    final replies = <ScraperReply>[];
    Completer<void>? wake;
    final host = ScraperHost(
      fetch: fetch,
      limits: limits,
      onLog: onLog,
      send: (reply) {
        replies.add(reply);
        if (wake != null && !wake!.isCompleted) wake!.complete();
      },
    );

    Future<List<ScraperStream>> conversation() async {
      await engine.evaluate(prelude);
      await engine.evaluate('__vx.run(${jsonEncode(code)}, ${jsonEncode(params.toJson())}, ${jsonEncode(libraries)})');
      while (true) {
        await engine.runPendingJobs();
        final out = jsonDecode(await engine.evaluate('__vx.take()'));
        if (out is List) out.forEach(host.handle);
        if (host.isDone) return host.result;
        if (replies.isEmpty) {
          if (host.pending == 0) throw const ScraperException('Le plug-in ne répond plus.');
          wake = Completer<void>();
          await wake!.future;
        }
        // Answers that arrive while these are delivered wait for the next turn.
        final batch = [...replies];
        replies.clear();
        for (final reply in batch) {
          await engine.evaluate(reply.toJs());
        }
      }
    }

    final running = conversation();
    try {
      return await running.timeout(limits.run);
    } on TimeoutException {
      throw const ScraperException('Le plug-in a mis trop de temps à répondre.');
    } finally {
      host.close();
      // A conversation abandoned on a timeout fails once its engine is gone: nobody waits for it.
      unawaited(running.then<void>((_) {}, onError: (_) {}));
      await engine.dispose();
    }
  }
}

/// Android / iOS: the JavaScript engine (`flutter_js`: QuickJS on Android, JavaScriptCore on iOS)
/// runs in its **own isolate**.
///
/// Why an isolate (for a Vue developer: think of a Web Worker): a scraper is somebody else's code
/// and may loop forever. In the app's own isolate that would freeze the screen and nothing could
/// stop it; in another one, the host just kills it when the time is up ([IsolateJsEngine.dispose]).
///
/// `flutter_js` is imported **only here**, behind the conditional import of `scraper_platform.dart`:
/// a web build never sees it.
///
/// Not verified yet on a device (`docs/scrapers.md` §9): the calls to `flutter_js` are written from
/// its documentation. `xhr: false` matters: the package's own `fetch` / `XMLHttpRequest` would let a
/// scraper reach the network without the host's checks.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';

import 'scraper_host.dart';
import 'scraper_models.dart';

class IsolateJsEngine implements JsEngine {
  IsolateJsEngine._(this._isolate, this._commands);

  /// Starts the isolate.
  static Future<IsolateJsEngine> start() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(_engineMain, handshake.sendPort);
    final commands = await handshake.first as SendPort;
    return IsolateJsEngine._(isolate, commands);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final _open = <ReceivePort>{};
  bool _killed = false;

  Future<String> _call(String op, [Object? argument]) async {
    if (_killed) throw const ScraperException('Le plug-in a été arrêté.');
    final reply = ReceivePort();
    _open.add(reply);
    try {
      _commands.send([reply.sendPort, op, argument]);
      final answer = await reply.first as List<Object?>;
      if (answer[0] != true) throw ScraperException('${answer[1]}');
      return '${answer[1]}';
    } on StateError {
      // The port was closed under us: the isolate was killed.
      throw const ScraperException('Le plug-in a été arrêté.');
    } finally {
      _open.remove(reply);
      reply.close();
    }
  }

  @override
  Future<String> evaluate(String source) => _call('eval', source);

  @override
  Future<void> runPendingJobs() async {
    await _call('jobs');
  }

  @override
  Future<void> dispose() async {
    if (_killed) return;
    // A polite goodbye first (the engine frees its memory); one that is stuck is killed anyway.
    try {
      await _call('dispose').timeout(const Duration(seconds: 2));
    } catch (_) {
      // Stuck or already gone.
    }
    _killed = true;
    for (final port in _open.toList()) {
      port.close();
    }
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// The isolate's entry point: answers `eval`, `jobs` and `dispose` commands, one at a time.
void _engineMain(SendPort handshake) {
  final commands = ReceivePort();
  handshake.send(commands.sendPort);
  JavascriptRuntime? runtime;
  commands.listen((Object? message) {
    final command = message as List<Object?>;
    final reply = command[0] as SendPort;
    try {
      switch (command[1]) {
        case 'eval':
          runtime ??= getJavascriptRuntime(xhr: false);
          final result = runtime!.evaluate(command[2] as String);
          reply.send([!result.isError, result.stringResult]);
        case 'jobs':
          final current = runtime;
          if (current != null) {
            // Bounded: a scraper that keeps queueing work does not keep this isolate for ever.
            for (var i = 0; i < 100000; i++) {
              if (current.executePendingJob() <= 0) break;
            }
          }
          reply.send([true, '']);
        case 'dispose':
          runtime?.dispose();
          runtime = null;
          reply.send([true, '']);
          commands.close();
        default:
          reply.send([false, 'commande inconnue']);
      }
    } catch (error) {
      reply.send([false, '$error']);
    }
  });
}

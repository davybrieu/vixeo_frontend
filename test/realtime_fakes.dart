import 'dart:async';
import 'dart:convert';

import 'package:vixeo/core/api/realtime.dart';

/// A WebSocket to Reverb, in memory: what the app sends, and what the server says.
class FakeSocket implements RealtimeSocket {
  final _frames = StreamController<Object?>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Stream<Object?> get frames => _frames.stream;

  @override
  void send(String frame) => sent.add(jsonDecode(frame) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    await _frames.close();
  }

  /// The server sends [event] (Pusher: `data` as a JSON string).
  void server(String event, Map<String, Object?> data, {String? channel}) =>
      _frames.add(jsonEncode({'event': event, 'data': jsonEncode(data), 'channel': ?channel}));

  /// The server goes away.
  Future<void> drop() => _frames.close();
}

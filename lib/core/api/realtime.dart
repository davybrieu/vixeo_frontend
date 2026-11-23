import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../config.dart';

/// A WebSocket, as [Realtime] uses it (a fake one in the tests).
abstract class RealtimeSocket {
  Stream<Object?> get frames;

  void send(String frame);

  Future<void> close();
}

/// Opens a [RealtimeSocket] to [uri].
typedef RealtimeConnector = Future<RealtimeSocket> Function(Uri uri);

/// Signs the private channel [channel] for the socket [socketId] (`auth` of
/// POST /api/broadcasting/auth).
typedef ChannelAuthorizer = Future<String?> Function(String socketId, String channel);

/// What a channel receives: an event of the server (`message.sent`, `notification`…) and its data,
/// or [Realtime.resync] after a reconnection.
class RealtimeEvent {
  const RealtimeEvent(this.name, [this.data = const {}]);

  final String name;
  final Map<String, dynamic> data;
}

/// The real-time channels of the API (vixeo_backend/docs/reverb.md): **one** WebSocket to Laravel
/// Reverb (the Pusher protocol) for the whole app, open while a channel is listened to, and one
/// private channel per subject: a conversation shown (`private-messages.{id}`, its page reads it
/// again when told it changed), or the notifications of Windows (`private-push-devices.{id}`,
/// while the app runs). Reconnects by itself (after 1 s, 2 s… 30 s at most) and then tells each
/// channel [resync]: what was announced meanwhile is read again. Without a Reverb key in the build,
/// nothing opens.
class Realtime {
  Realtime({required ChannelAuthorizer authorize, RealtimeConnector? connect, Uri? endpoint})
    : _authorize = authorize, // ignore: prefer_initializing_formals
      _connect = connect ?? connectWebSocket,
      _endpoint = endpoint ?? defaultEndpoint;

  /// Reverb of this build (`REVERB_*` of `--dart-define`); null without a key.
  static Uri? get defaultEndpoint => AppConfig.reverbAppKey.isEmpty
      ? null
      : Uri(
          scheme: AppConfig.reverbScheme == 'https' ? 'wss' : 'ws',
          host: AppConfig.reverbHost,
          port: AppConfig.reverbPort,
          path: '/app/${AppConfig.reverbAppKey}',
          queryParameters: const {'protocol': '7', 'client': 'vixeo', 'version': '1.0', 'flash': 'false'},
        );

  /// What a channel receives after a reconnection: events may have been missed.
  static const resync = 'resync';

  final ChannelAuthorizer _authorize;
  final RealtimeConnector _connect;
  final Uri? _endpoint;

  final _channels = <String, StreamController<RealtimeEvent>>{};

  /// Channels to tell [resync] once subscribed again.
  final _missed = <String>{};
  RealtimeSocket? _socket;
  StreamSubscription<Object?>? _frames;
  String? _socketId;
  Timer? _retry;
  int _attempts = 0;
  bool _connecting = false;
  bool _disposed = false;

  bool get enabled => _endpoint != null;

  /// The events of the private channel [channel] (`private-…`), while listened to (the socket
  /// opens with the first channel listened to and closes with the last one).
  Stream<RealtimeEvent> events(String channel) {
    final existing = _channels[channel];
    if (existing != null) return existing.stream;
    late final StreamController<RealtimeEvent> controller;
    controller = StreamController<RealtimeEvent>.broadcast(
      onListen: () => _subscribe(channel),
      onCancel: () {
        if (identical(_channels[channel], controller)) _channels.remove(channel);
        _missed.remove(channel);
        _send('pusher:unsubscribe', {'channel': channel});
        unawaited(controller.close());
        if (_channels.isEmpty) _disconnect();
      },
    );
    _channels[channel] = controller;
    return controller.stream;
  }

  void dispose() {
    _disposed = true;
    _disconnect();
    for (final channel in _channels.values.toList()) {
      unawaited(channel.close());
    }
    _channels.clear();
  }

  void _subscribe(String channel) {
    if (!enabled || _disposed) return;
    final socketId = _socketId;
    if (_socket != null && socketId != null) {
      unawaited(_authorizeChannel(channel, socketId));
    } else {
      unawaited(_open());
    }
  }

  Future<void> _open() async {
    final endpoint = _endpoint;
    if (endpoint == null || _disposed || _connecting || _socket != null || _channels.isEmpty) return;
    _connecting = true;
    try {
      final socket = await _connect(endpoint);
      if (_disposed || _channels.isEmpty) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _frames = socket.frames.listen(
        (frame) => _onFrame(socket, frame),
        onDone: () => _lost(socket),
        onError: (Object _) => _lost(socket),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _onFrame(RealtimeSocket socket, Object? frame) {
    if (!identical(socket, _socket) || frame is! String) return;
    final envelope = _decode(frame);
    if (envelope == null) return;
    final event = envelope['event'];
    final channel = envelope['channel'];
    final raw = envelope['data'];
    final data = raw is String ? _decode(raw) : (raw is Map<String, dynamic> ? raw : null);
    switch (event) {
      case 'pusher:connection_established':
        final socketId = data?['socket_id'];
        if (socketId is! String) return;
        _socketId = socketId;
        _attempts = 0;
        for (final name in _channels.keys.toList()) {
          unawaited(_authorizeChannel(name, socketId));
        }
      case 'pusher:ping':
        _send('pusher:pong', const {});
      case 'pusher_internal:subscription_succeeded':
        if (channel is String && _missed.remove(channel)) _channels[channel]?.add(const RealtimeEvent(resync));
      case final String name when !name.startsWith('pusher:') && !name.startsWith('pusher_internal:'):
        if (channel is String) _channels[channel]?.add(RealtimeEvent(name, data ?? const {}));
    }
  }

  Future<void> _authorizeChannel(String channel, String socketId) async {
    try {
      final auth = await _authorize(socketId, channel);
      // Still the same connection, and still listened to.
      if (auth == null || socketId != _socketId || !_channels.containsKey(channel)) return;
      _send('pusher:subscribe', {'auth': auth, 'channel': channel});
    } catch (_) {
      // Refused (not a member any more, signed out) or offline: the pages still read the API.
    }
  }

  void _send(String event, Map<String, Object?> data) {
    try {
      _socket?.send(jsonEncode({'event': event, 'data': data}));
    } catch (_) {
      // Closing: the reconnection subscribes again.
    }
  }

  void _lost(RealtimeSocket socket) {
    if (!identical(socket, _socket)) return;
    _socket = null;
    _socketId = null;
    _frames = null;
    _missed.addAll(_channels.keys);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || _channels.isEmpty || (_retry?.isActive ?? false)) return;
    _attempts++;
    _retry = Timer(Duration(seconds: math.min(_attempts, 30)), () => unawaited(_open()));
  }

  void _disconnect() {
    _retry?.cancel();
    _retry = null;
    _attempts = 0;
    unawaited(_frames?.cancel());
    _frames = null;
    final socket = _socket;
    _socket = null;
    _socketId = null;
    if (socket != null) unawaited(socket.close());
  }

  static Map<String, dynamic>? _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }
}

/// A WebSocket of `dart:io` (Android, Windows, iOS: there is no web version), with a ping every
/// 25 s so that a dead connection is noticed.
Future<RealtimeSocket> connectWebSocket(Uri uri) async {
  final socket = await WebSocket.connect(uri.toString());
  socket.pingInterval = const Duration(seconds: 25);
  return _IoSocket(socket);
}

class _IoSocket implements RealtimeSocket {
  _IoSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get frames => _socket;

  @override
  void send(String frame) => _socket.add(frame);

  @override
  Future<void> close() => _socket.close();
}

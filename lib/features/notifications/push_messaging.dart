import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A notification received while the app is open: a push (Android shows the others itself), or
/// the `notification` event of the real-time channel of Windows.
class PushNotification {
  const PushNotification({required this.title, required this.body, this.path, this.channel});

  /// The `notification` event of the real-time channel (`App\Events\PushNotified` of the API).
  factory PushNotification.fromRealtime(Map<String, dynamic> data) {
    final path = data['path'];
    return PushNotification(
      title: data['title'] as String? ?? 'Vixeo',
      body: data['body'] as String? ?? '',
      path: path is String && path.startsWith('/') ? path : null,
      channel: data['channel'] as String?,
    );
  }

  final String title;
  final String body;

  /// The page a tap opens (`data.path`), e.g. /titre/tv/1399.
  final String? path;

  /// Android channel given by the server (`episodes`, `general`, `social`).
  final String? channel;
}

/// Push notifications sent by the Vixeo server through Firebase Cloud Messaging
/// (vixeo_backend/docs/notifications.md): the app only gives its Firebase installation ID to the
/// API (`PushRegistration`). Android (iOS ready); not on Windows (no Firebase Messaging there: the
/// real-time channel, `PushTransport.realtime`). A fake in tests.
abstract class PushMessaging {
  /// False on Windows.
  bool get supported;

  /// This app's Firebase installation ID (FID), the target of the server's messages; null when the
  /// build has no Firebase project (docs/android-release.md) or Google Play services are missing.
  Future<String?> installationId();

  /// Firebase gave this app another installation ID: registered again.
  Stream<String> get installationIdChanges;

  /// Received while the app is open.
  Stream<PushNotification> get received;

  /// Page of a notification tapped while the app was in the background.
  Stream<String> get opened;

  /// Page of the notification that launched the app, once (null afterwards).
  Future<String?> launchPath();
}

/// firebase_messaging. Firebase is set up from the Android resources the build writes from the
/// FIREBASE_* secrets (android/app/build.gradle.kts): no google-services.json in the repository.
/// The app is identified by its Firebase installation ID (`register()` / `onRegistered`, which
/// replace the token of `getToken()` since firebase_messaging 17; Android needs the
/// `firebase_messaging_installation_id_enabled` meta-data of the manifest). Every call is guarded:
/// push never breaks the app.
class FirebasePushMessaging implements PushMessaging {
  Future<FirebaseMessaging?>? _ready;
  bool _launchRead = false;

  /// The last installation ID given by `onRegistered`.
  String? _fid;
  Completer<String?>? _registering;
  final _changes = StreamController<String>.broadcast();

  /// How long `register()` may take to give the installation ID.
  static const registerTimeout = Duration(seconds: 30);

  @override
  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<FirebaseMessaging?> _messaging() => _ready ??= () async {
    if (!supported) return null;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      // Listened to before the first register(): its answer comes by onRegistered, and so does
      // every later change (Firebase may replace the ID).
      messaging.onRegistered.listen(_registered, onError: (Object _) {});
      messaging.onUnregistered.listen((fid) {
        if (fid == _fid) _fid = null;
      }, onError: (Object _) {});
      return messaging;
    } catch (e) {
      debugPrint('Push unavailable (no Firebase project in this build?): $e');
      return null;
    }
  }();

  void _registered(String fid) {
    final previous = _fid;
    _fid = fid;
    final waiting = _registering;
    if (waiting != null && !waiting.isCompleted) waiting.complete(fid);
    if (previous != null && previous != fid) _changes.add(fid);
  }

  @override
  Future<String?> installationId() async {
    final messaging = await _messaging();
    if (messaging == null) return null;
    final known = _fid;
    if (known != null) return known;
    final running = _registering;
    if (running != null && !running.isCompleted) return running.future;
    final waiting = _registering = Completer<String?>();
    try {
      await messaging.register();
      return await waiting.future.timeout(registerTimeout, onTimeout: () => _fid);
    } catch (e) {
      debugPrint('No Firebase installation ID: $e');
      return _fid;
    } finally {
      if (!waiting.isCompleted) waiting.complete(_fid);
    }
  }

  Stream<T> _stream<T>(Stream<T> Function(FirebaseMessaging messaging) of) async* {
    final messaging = await _messaging();
    if (messaging != null) yield* of(messaging);
  }

  @override
  Stream<String> get installationIdChanges => _changes.stream;

  @override
  Stream<PushNotification> get received => _stream((_) => FirebaseMessaging.onMessage.map(_notification));

  @override
  Stream<String> get opened =>
      _stream((_) => FirebaseMessaging.onMessageOpenedApp.map(_path).where((path) => path != null).cast<String>());

  @override
  Future<String?> launchPath() async {
    if (_launchRead) return null;
    _launchRead = true;
    final messaging = await _messaging();
    if (messaging == null) return null;
    try {
      final message = await messaging.getInitialMessage();
      return message == null ? null : _path(message);
    } catch (_) {
      return null;
    }
  }

  static String? _path(RemoteMessage message) {
    final path = message.data['path'];
    return path is String && path.startsWith('/') ? path : null;
  }

  static PushNotification _notification(RemoteMessage message) => PushNotification(
    title: message.notification?.title ?? 'Vixeo',
    body: message.notification?.body ?? '',
    path: _path(message),
    channel: message.notification?.android?.channelId,
  );
}

final pushMessagingProvider = Provider<PushMessaging>((ref) => FirebasePushMessaging());

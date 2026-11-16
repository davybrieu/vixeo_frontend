import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A push notification received while the app is open (Android shows the others itself).
class PushNotification {
  const PushNotification({required this.title, required this.body, this.path, this.channel});

  final String title;
  final String body;

  /// The page a tap opens (`data.path`), e.g. /titre/tv/1399.
  final String? path;

  /// Android channel given by the server (`episodes`, `general`).
  final String? channel;
}

/// Push notifications sent by the Vixeo server through Firebase Cloud Messaging
/// (vixeo_backend/docs/notifications.md): the app only gives its token to the API
/// (`PushRegistration`). Android (iOS ready); not in a browser. A fake in tests.
abstract class PushMessaging {
  /// False in a browser.
  bool get supported;

  /// This app's FCM token; null when the build has no Firebase project (docs/android-release.md)
  /// or Google Play services are missing.
  Future<String?> token();

  /// FCM replaced the token: registered again.
  Stream<String> get tokenRefresh;

  /// Received while the app is open.
  Stream<PushNotification> get received;

  /// Page of a notification tapped while the app was in the background.
  Stream<String> get opened;

  /// Page of the notification that launched the app, once (null afterwards).
  Future<String?> launchPath();
}

/// firebase_messaging. Firebase is set up from the Android resources the build writes from the
/// FIREBASE_* secrets (android/app/build.gradle.kts): no google-services.json in the repository.
/// Every call is guarded: push never breaks the app.
class FirebasePushMessaging implements PushMessaging {
  Future<FirebaseMessaging?>? _ready;
  bool _launchRead = false;

  @override
  bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<FirebaseMessaging?> _messaging() => _ready ??= () async {
    if (!supported) return null;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return FirebaseMessaging.instance;
    } catch (e) {
      debugPrint('Push unavailable (no Firebase project in this build?): $e');
      return null;
    }
  }();

  @override
  Future<String?> token() async {
    final messaging = await _messaging();
    if (messaging == null) return null;
    try {
      return await messaging.getToken();
    } catch (e) {
      debugPrint('No push token: $e');
      return null;
    }
  }

  Stream<T> _stream<T>(Stream<T> Function(FirebaseMessaging messaging) of) async* {
    final messaging = await _messaging();
    if (messaging != null) yield* of(messaging);
  }

  @override
  Stream<String> get tokenRefresh => _stream((messaging) => messaging.onTokenRefresh);

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

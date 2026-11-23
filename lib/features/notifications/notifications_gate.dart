import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router.dart';
import '../auth/session.dart';
import '../messages/messages.dart' show inboxProvider, unreadMessagesProvider;
import 'episode_alerts.dart';
import 'inbox.dart';
import 'push_messaging.dart';
import 'push_registration.dart';
import 'system_notifications.dart';

/// Around the app (`MaterialApp.builder`), like UpdateGate: prepares the notification channels,
/// registers the app with the server (at launch, back in the foreground, when the session, the
/// profile, the « Nouveaux épisodes » or « Activité » setting or the Firebase installation ID
/// changes), shows a notification received while the app is open (a push, or on Windows an event
/// of its real-time channel: [realtimeNotificationsProvider]), and opens the page of a tapped
/// notification (also one that launched the app). Nothing on a Windows build without Reverb.
class NotificationsGate extends ConsumerStatefulWidget {
  const NotificationsGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationsGate> createState() => _NotificationsGateState();
}

class _NotificationsGateState extends ConsumerState<NotificationsGate> {
  late final PushTransport _transport = ref.read(pushTransportProvider);
  AppLifecycleListener? _lifecycle;
  final _subscriptions = <StreamSubscription<Object?>>[];
  int _shown = 0;

  bool get _supported => _transport != PushTransport.none;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    _lifecycle = AppLifecycleListener(onResume: _register);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final system = ref.read(systemNotificationsProvider);
    final push = ref.read(pushMessagingProvider);
    await system.init(_open);
    if (!mounted) return;
    if (_transport == PushTransport.firebase) {
      _subscriptions
        ..add(push.received.listen(_show))
        ..add(push.opened.listen(_open))
        ..add(push.installationIdChanges.listen((_) => ref.read(pushRegistrationProvider).sync(force: true)));
    }
    final path = (_transport == PushTransport.firebase ? await push.launchPath() : null) ?? await system.launchPath();
    if (path != null) _open(path);
    _register();
  }

  void _register() => ref.read(pushRegistrationProvider).sync();

  /// Android only shows the push of a closed app: the app shows the others itself, and those of
  /// the real-time channel (Windows). One of the `social` channel also updates the badges and the
  /// « Notifications » and « Messages » pages.
  void _show(PushNotification notification) {
    if (notification.channel == NotificationChannel.social.id) {
      ref.read(unreadNotificationsProvider.notifier).refresh(force: true);
      // Messages are pushed on this channel too.
      ref.read(unreadMessagesProvider.notifier).refresh(force: true);
      ref.invalidate(inboxProvider);
      ref
        ..invalidate(activityFeedProvider)
        ..invalidate(followRequestsProvider);
    }
    ref
        .read(systemNotificationsProvider)
        .show(
          LocalNotification(
            // Positive, never 0, different each time.
            id: 1000 + (_shown++ % 100000),
            title: notification.title,
            body: notification.body,
            path: notification.path,
            channel: NotificationChannel.of(notification.channel),
          ),
        );
  }

  /// A notification's page. Before the session is ready, the router keeps it and opens it once
  /// a profile is chosen.
  void _open(String path) {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final session = ref.read(sessionProvider);
    if (session.status == SessionStatus.signedIn && session.profile != null) {
      router.push(path);
    } else {
      router.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_supported) {
      ref.listen(sessionProvider.select((s) => (s.status, s.token, s.profile?.id)), (previous, next) {
        if (previous != next) _register();
      });
      // Turned on or off (not its first reading: the launch registers already).
      void changed(AsyncValue<bool>? previous, AsyncValue<bool> next) {
        if (previous != null && previous.hasValue && next.hasValue && previous.value != next.value) {
          ref.read(pushRegistrationProvider).sync(force: true);
        }
      }

      ref.listen(episodeAlertsSettingProvider, changed);
      ref.listen(socialAlertsSettingProvider, changed);
      if (_transport == PushTransport.realtime) {
        // Keeps the channel open while the app runs (the provider is not autoDispose).
        // Each event once (not again when the provider reloads: another profile, another session).
        ref.listen(realtimeNotificationsProvider, (previous, next) {
          if (next case AsyncData(:final value) when !identical(value, previous?.value)) _show(value);
        });
      }
    }
    return widget.child;
  }
}

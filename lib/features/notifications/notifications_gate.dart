import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router.dart';
import '../auth/session.dart';
import 'episode_alerts.dart';
import 'inbox.dart';
import 'push_messaging.dart';
import 'push_registration.dart';
import 'system_notifications.dart';

/// Around the app (`MaterialApp.builder`), like UpdateGate: prepares the notification channels,
/// registers the app with the server (at launch, back in the foreground, when the session, the
/// profile, the « Nouveaux épisodes » or « Activité » setting or the push token changes), shows a push received
/// while the app is open, and opens the page of a tapped notification (also one that launched
/// the app). Nothing on Windows.
class NotificationsGate extends ConsumerStatefulWidget {
  const NotificationsGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationsGate> createState() => _NotificationsGateState();
}

class _NotificationsGateState extends ConsumerState<NotificationsGate> {
  late final bool _supported = ref.read(pushMessagingProvider).supported;
  AppLifecycleListener? _lifecycle;
  final _subscriptions = <StreamSubscription<Object?>>[];
  int _shown = 0;

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
    _subscriptions
      ..add(push.received.listen(_show))
      ..add(push.opened.listen(_open))
      ..add(push.tokenRefresh.listen((_) => ref.read(pushRegistrationProvider).sync(force: true)));
    final path = await push.launchPath() ?? await system.launchPath();
    if (path != null) _open(path);
    _register();
  }

  void _register() => ref.read(pushRegistrationProvider).sync();

  /// Android only shows the push of a closed app: the app shows the others itself. One of the
  /// `social` channel also updates the badge and the « Notifications » page.
  void _show(PushNotification notification) {
    if (notification.channel == NotificationChannel.social.id) {
      ref.read(unreadNotificationsProvider.notifier).refresh(force: true);
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
    }
    return widget.child;
  }
}

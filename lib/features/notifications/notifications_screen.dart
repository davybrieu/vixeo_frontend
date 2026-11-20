import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../profiles/settings_rows.dart';
import 'episode_alerts.dart';
import 'push_registration.dart';
import 'system_notifications.dart';

/// « Notifications » (Paramètres): the new-episode alerts of the profile's « Ma liste » shows on
/// this device, and a test notification. The server sends them (push, docs:
/// vixeo_backend/docs/notifications.md); Windows can't receive them (no Firebase Messaging there).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  static const location = '/profil/notifications';

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late final AppLifecycleListener _lifecycle;

  /// Allowed by the system (null: not known yet).
  bool? _allowed;
  bool _sending = false;

  SystemNotifications get _notifications => ref.read(systemNotificationsProvider);

  @override
  void initState() {
    super.initState();
    // Back from the system settings: read the answer again.
    _lifecycle = AppLifecycleListener(onResume: _checkAllowed);
    _checkAllowed();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkAllowed() async {
    if (!_notifications.supported) return;
    final allowed = await _notifications.allowed();
    if (mounted) setState(() => _allowed = allowed);
  }

  /// Allowed, after the system's question if needed. False: a message says where to allow them.
  Future<bool> _permission() async {
    final allowed = _allowed == true || await _notifications.requestPermission();
    if (!mounted) return allowed;
    setState(() => _allowed = allowed);
    if (!allowed) {
      showVxSnack(
        context,
        'Autorisez les notifications de Vixeo dans les réglages de l’appareil.',
        icon: Icons.notifications_off_outlined,
      );
    }
    return allowed;
  }

  Future<void> _toggle(bool value) async {
    if (value && !await _permission()) return;
    // NotificationsGate sends the new setting to the server.
    await ref.read(episodeAlertsSettingProvider.notifier).set(value);
    if (!mounted) return;
    showVxSnack(
      context,
      value ? 'Alertes de nouveaux épisodes activées' : 'Alertes de nouveaux épisodes désactivées',
      icon: value ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
    );
  }

  Future<void> _sendTest() async {
    if (!await _permission()) return;
    setState(() => _sending = true);
    String message;
    var failed = false;
    try {
      message = await ref.read(pushRegistrationProvider).sendTest();
    } on ApiException catch (e) {
      message = e.message;
      failed = true;
    } on PushUnavailable catch (e) {
      message = e.message;
      failed = true;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    showVxSnack(context, message, icon: failed ? Icons.error_outline_rounded : Icons.notifications_active_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final availability = ref.watch(pushAvailabilityProvider);

    if (availability.value == PushAvailability.unsupported || !_notifications.supported) {
      return const InfoPage(
        title: 'Notifications',
        fallback: '/parametres',
        children: [InfoIntro('Les notifications sont disponibles dans l’appli Android.')],
      );
    }

    final ready = availability.value == PushAvailability.ready;
    final enabled = ref.watch(episodeAlertsSettingProvider).value ?? false;

    return InfoPage(
      title: 'Notifications',
      fallback: '/parametres',
      children: [
        // Why not (two different fixes): this version of the app has no Firebase configuration (a
        // newer APK built with the FIREBASE_* secrets), or the server sends none (FCM_CREDENTIALS).
        if (availability.value == PushAvailability.noToken) ...[
          const _Notice(
            icon: Icons.system_update_outlined,
            title: 'Bientôt disponibles',
            text: 'Cette version de l’appli ne reçoit pas encore les notifications. Installez la dernière version.',
          ),
          SizedBox(height: 24 * s),
        ] else if (availability.value == PushAvailability.serverOff) ...[
          const _Notice(
            icon: Icons.notifications_paused_outlined,
            title: 'Bientôt disponibles',
            text: 'Le serveur n’envoie pas encore de notifications.',
          ),
          SizedBox(height: 24 * s),
        ] else if (_allowed == false) ...[
          _Notice(
            icon: Icons.notifications_off_outlined,
            title: 'Notifications bloquées',
            text: 'Les notifications de Vixeo sont désactivées dans les réglages de l’appareil.',
            action: VxButton(
              label: 'Ouvrir les réglages',
              icon: Icons.settings_outlined,
              kind: VxButtonKind.secondary,
              onPressed: _notifications.openSettings,
            ),
          ),
          SizedBox(height: 24 * s),
        ],
        SettingsSection(
          'Alertes',
          scale: s,
          children: [
            SettingsSwitchRow(
              label: 'Nouveaux épisodes',
              detail: 'Quand un nouvel épisode d’une série de Ma liste sort.',
              value: enabled,
              autofocus: true,
              onChanged: ready ? _toggle : null,
            ),
          ],
        ),
        SettingsSection(
          'Test',
          scale: s,
          last: true,
          children: [
            SettingsActionRow(
              icon: Icons.notifications_active_outlined,
              label: 'Envoyer une notification de test',
              detail: 'Pour vérifier que les notifications arrivent sur cet appareil.',
              busy: _sending,
              onPressed: ready ? _sendTest : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Why the notifications can't come (not available yet, blocked by the system).
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.text, this.action});

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return VxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22 * s, color: VxColors.dangerText),
              SizedBox(width: 10 * s),
              Expanded(child: Text(title, style: VxText.title(17 * s))),
            ],
          ),
          SizedBox(height: 8 * s),
          Text(text, style: VxText.body(14 * s, color: VxColors.textSecondary)),
          if (action != null) ...[SizedBox(height: 14 * s), action!],
        ],
      ),
    );
  }
}

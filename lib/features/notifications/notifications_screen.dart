import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../library/library.dart';
import '../profiles/settings_rows.dart';
import 'episode_alerts.dart';
import 'system_notifications.dart';

/// « Notifications » (Paramètres): the new-episode alerts of the profile's « Ma liste » shows, on
/// this device, the coming ones, and a test notification. Local notifications programmed by the
/// app (docs: vixeo_backend/docs/notifications.md); a browser can't program them.
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
    await ref.read(episodeAlertsSettingProvider.notifier).set(value);
    if (!mounted) return;
    showVxSnack(
      context,
      value ? 'Alertes de nouveaux épisodes activées' : 'Alertes de nouveaux épisodes désactivées',
      icon: value ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
    );
  }

  /// A show of « Ma liste » for the example, if there is one.
  ({int id, String title})? _exampleShow() {
    final library = ref.read(libraryProvider).value;
    if (library == null) return null;
    for (final item in library.favorites) {
      final title = item.tmdbTitle;
      if (item.type == 'tv' && title?.type == MediaType.tv && item.title.isNotEmpty) {
        return (id: title!.id, title: item.title);
      }
    }
    return null;
  }

  Future<void> _sendTest() async {
    if (!await _permission()) return;
    setState(() => _sending = true);
    final show = _exampleShow();
    await _notifications.show(
      LocalNotification(
        id: testNotificationId,
        title: show?.title ?? 'Vixeo',
        body: show == null
            ? 'Test : les notifications de Vixeo fonctionnent.'
            : 'Test : les nouveaux épisodes arriveront comme ceci.',
        path: show == null ? NotificationsScreen.location : titlePath(MediaType.tv, show.id),
      ),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    showVxSnack(context, 'Notification de test envoyée', icon: Icons.notifications_active_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);

    if (!_notifications.supported) {
      return const InfoPage(
        title: 'Notifications',
        fallback: '/parametres',
        children: [
          InfoIntro(
            'Les notifications sont disponibles dans l’appli Android : un navigateur ne peut pas les programmer.',
          ),
        ],
      );
    }

    final enabled = ref.watch(episodeAlertsSettingProvider).value ?? false;
    ref.watch(libraryProvider);
    final example = _exampleShow();

    return InfoPage(
      title: 'Notifications',
      fallback: '/parametres',
      children: [
        if (_allowed == false) ...[
          _Blocked(onOpenSettings: _notifications.openSettings),
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
              onChanged: _toggle,
            ),
          ],
        ),
        if (enabled) const _ComingAlerts(),
        SettingsSection(
          'Test',
          scale: s,
          last: true,
          children: [
            SettingsActionRow(
              icon: Icons.notifications_active_outlined,
              label: 'Envoyer une notification de test',
              detail: example == null
                  ? 'Pour vérifier que les notifications arrivent.'
                  : 'Une notification d’exemple pour « ${example.title} ».',
              busy: _sending,
              onPressed: _sendTest,
            ),
          ],
        ),
      ],
    );
  }
}

/// The system refuses Vixeo's notifications: where to allow them.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return VxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_off_outlined, size: 22 * s, color: VxColors.dangerText),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text('Notifications bloquées', style: VxText.title(17 * s)),
              ),
            ],
          ),
          SizedBox(height: 8 * s),
          Text(
            'Les notifications de Vixeo sont désactivées dans les réglages de l’appareil.',
            style: VxText.body(14 * s, color: VxColors.textSecondary),
          ),
          SizedBox(height: 14 * s),
          VxButton(
            label: 'Ouvrir les réglages',
            icon: Icons.settings_outlined,
            kind: VxButtonKind.secondary,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

/// « Prochaines alertes »: what is programmed, the soonest first (10 shown).
class _ComingAlerts extends ConsumerWidget {
  const _ComingAlerts();

  static const shown = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final alerts = ref.watch(upcomingAlertsProvider);
    final now = DateTime.now();

    Widget message(String text) => Text(text, style: VxText.body(14 * s, color: VxColors.textSecondary));

    return SettingsSection(
      'Prochaines alertes',
      scale: s,
      children: [
        switch (alerts) {
          AsyncData(:final value) when value.isEmpty => message(
            'Aucun nouvel épisode annoncé dans les 60 prochains jours pour les séries de Ma liste.',
          ),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, alert) in value.take(shown).indexed) ...[
                if (i > 0) SizedBox(height: 8 * s),
                _AlertRow(alert: alert, when: alertDateLabel(alert.at, now: now)),
              ],
            ],
          ),
          AsyncError() => message('Les prochains épisodes ne sont pas disponibles pour le moment.'),
          _ => Padding(
            padding: EdgeInsets.symmetric(vertical: 8 * s),
            child: const Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.when});

  final EpisodeAlert alert;
  final String when;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final poster = alert.episodes.first.posterUrl;
    return VxFocusable(
      borderRadius: 14 * s,
      focusScale: 1.02,
      semanticLabel: '${alert.showName}, ${alert.codes}, $when',
      onPressed: () => context.push(alert.path),
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.all(10 * s),
          decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * s)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8 * s),
                child: SizedBox(
                  width: 40 * s,
                  height: 60 * s,
                  child: NetImage(url: poster, seed: alert.showId),
                ),
              ),
              SizedBox(width: 12 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.showName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(15 * s, weight: FontWeight.w600),
                    ),
                    SizedBox(height: 2 * s),
                    Text(alert.codes, style: VxText.body(13 * s, color: VxColors.textSecondary)),
                    Text(when, style: VxText.body(13 * s, color: VxColors.accent, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

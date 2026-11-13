import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../catalog/catalog_repository.dart';
import '../tv/channel_row.dart';
import 'row_preferences.dart';

/// A row of a page, as the settings list it: its key in [RowPreferences] and its name.
typedef _RowEntry = ({String key, String title});

/// « Rangées de l’accueil » / « Catégories des chaînes TV »: the rows of the page, to move up or
/// down and to show or hide. Kept on the device, for the active profile.
class RowsSettingsScreen extends ConsumerWidget {
  const RowsSettingsScreen({super.key, required this.page});

  final RowsPage page;

  static const homeLocation = '/profil/rangees/accueil';
  static const channelsLocation = '/profil/rangees/chaines-tv';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = page == RowsPage.home;
    // The rows as the page would show them without any preference.
    final AsyncValue<List<_RowEntry>> rows = home
        ? ref.watch(homeProvider).whenData((h) => [for (final s in h.sections) (key: s.key, title: s.title)])
        : ref
              .watch(tvChannelRowsProvider)
              .whenData((sections) => [for (final s in sections) (key: channelRowKey(s), title: s.title)]);
    final preferences =
        (home ? ref.watch(homeRowPreferencesProvider) : ref.watch(channelRowPreferencesProvider)).value ??
        RowPreferences.none;

    void save(RowPreferences value) {
      final RowPreferencesController controller = home
          ? ref.read(homeRowPreferencesProvider.notifier)
          : ref.read(channelRowPreferencesProvider.notifier);
      controller.save(value);
    }

    return InfoPage(
      title: home ? 'Rangées de l’accueil' : 'Catégories des chaînes TV',
      fallback: '/profil',
      children: [
        InfoIntro(
          home
              ? 'Choisissez l’ordre des rangées de l’accueil et celles à afficher. '
                    'Ce réglage est gardé sur cet appareil, pour ce profil.'
              : 'Choisissez l’ordre des catégories de la page Chaînes TV et celles à afficher. '
                    'Ce réglage est gardé sur cet appareil, pour ce profil.',
        ),
        AsyncView(
          value: rows,
          onRetry: () => ref.invalidate(home ? homeProvider : tvChannelRowsProvider),
          data: (all) {
            if (all.isEmpty) {
              return const EmptyState(icon: Icons.view_stream_outlined, title: 'Aucune rangée pour l’instant');
            }
            final sorted = preferences.sorted(all, (row) => row.key);
            final keys = [for (final row in sorted) row.key];

            void move(int from, int to) {
              final order = [...keys];
              order.insert(to, order.removeAt(from));
              save(RowPreferences(order: order, hidden: preferences.hidden));
            }

            void toggle(String key) {
              final hidden = {...preferences.hidden};
              if (!hidden.remove(key)) hidden.add(key);
              save(RowPreferences(order: preferences.order, hidden: hidden));
            }

            final gap = SizedBox(height: Layout.of(context).listGap);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, row) in sorted.indexed) ...[
                  if (i > 0) gap,
                  _RowLine(
                    title: row.title,
                    hidden: preferences.isHidden(row.key),
                    onUp: i == 0 ? null : () => move(i, i - 1),
                    onDown: i == sorted.length - 1 ? null : () => move(i, i + 1),
                    onToggle: () => toggle(row.key),
                  ),
                ],
                if (!preferences.isDefault) ...[
                  SizedBox(height: Layout.of(context).sectionGap),
                  VxButton(
                    label: 'Réinitialiser',
                    kind: VxButtonKind.outline,
                    onPressed: () => save(RowPreferences.none),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One row of the page: its name, then « monter », « descendre » and « afficher / masquer ».
/// Buttons rather than drag and drop: they also work with a TV remote.
class _RowLine extends StatelessWidget {
  const _RowLine({
    required this.title,
    required this.hidden,
    required this.onUp,
    required this.onDown,
    required this.onToggle,
  });

  final String title;
  final bool hidden;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final gap = SizedBox(width: layout.size(6, tv: 14));
    return VxCard(
      padding: EdgeInsets.symmetric(horizontal: layout.size(14, tv: 24), vertical: layout.size(8, tv: 14)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(
                15 * s,
                weight: FontWeight.w600,
                color: hidden ? VxColors.textSecondary : VxColors.text,
              ),
            ),
          ),
          gap,
          Opacity(
            opacity: onUp == null ? 0.3 : 1,
            child: VxIconAction(
              dense: true,
              icon: Icons.arrow_upward_rounded,
              label: 'Monter : $title',
              onPressed: onUp,
            ),
          ),
          gap,
          Opacity(
            opacity: onDown == null ? 0.3 : 1,
            child: VxIconAction(
              dense: true,
              icon: Icons.arrow_downward_rounded,
              label: 'Descendre : $title',
              onPressed: onDown,
            ),
          ),
          gap,
          VxIconAction(
            dense: true,
            icon: hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            label: hidden ? 'Afficher : $title' : 'Masquer : $title',
            active: !hidden,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

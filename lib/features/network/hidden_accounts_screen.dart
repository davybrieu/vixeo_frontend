import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../social/profile_view.dart' show AccountTile;
import '../social/social_repository.dart';
import 'network.dart';
import 'widgets.dart';

/// « Comptes bloqués et masqués » (« ⋮ » of the « Profil » page, vixeo_backend/docs/moderation.md):
/// the blocked accounts (« Débloquer ») and the accounts hidden from the feed (« Réafficher »).
class HiddenAccountsScreen extends ConsumerStatefulWidget {
  const HiddenAccountsScreen({super.key});

  static const location = '/profil/comptes-masques';

  @override
  ConsumerState<HiddenAccountsScreen> createState() => _HiddenAccountsScreenState();
}

class _HiddenAccountsScreenState extends ConsumerState<HiddenAccountsScreen> {
  final _busy = <String>{};

  Future<void> _restore(SocialProfile member, {required bool blocked}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(member.username));
    try {
      final repository = ref.read(networkRepositoryProvider);
      if (blocked) {
        await repository.block(member.username, blocked: false);
      } else {
        await repository.mute(member.username, muted: false);
      }
      ref.invalidate(hiddenAccountsProvider);
      ref.invalidate(feedProvider);
      ref.invalidate(socialProfileProvider(member.username));
      showVxSnackOn(
        messenger,
        blocked ? '@${member.username} est débloqué' : '@${member.username} revient dans votre fil',
        icon: Icons.check_rounded,
      );
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy.remove(member.username));
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final hidden = ref.watch(hiddenAccountsProvider);
    final value = hidden.value;

    Widget group(String title, List<SocialProfile> members, {required bool blocked}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: VxText.title(layout.sectionTitleSize)),
        SizedBox(height: layout.space(VxSpace.xxs)),
        Text(
          blocked
              ? 'Ni vous ni eux ne voyez ce que l’autre publie, ni ne pouvez vous suivre ou vous écrire.'
              : 'Leurs publications n’apparaissent plus dans votre fil ; ils ne sont pas prévenus.',
          style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
        ),
        SizedBox(height: layout.titleGap),
        if (members.isEmpty)
          Text(
            blocked ? 'Aucun compte bloqué.' : 'Aucun compte masqué.',
            style: VxText.body(layout.bodySize, color: VxColors.textMuted),
          ),
        for (final member in members)
          Padding(
            padding: EdgeInsets.only(bottom: layout.space(VxSpace.xs)),
            child: Row(
              children: [
                Expanded(child: AccountTile(profile: member)),
                SizedBox(width: layout.space(VxSpace.s)),
                VxButton(
                  label: blocked ? 'Débloquer' : 'Réafficher',
                  kind: VxButtonKind.outline,
                  dense: true,
                  loading: _busy.contains(member.username),
                  onPressed: () => _restore(member, blocked: blocked),
                ),
              ],
            ),
          ),
      ],
    );

    return NetworkPage(
      title: 'Comptes bloqués et masqués',
      onRefresh: () async {
        ref.invalidate(hiddenAccountsProvider);
      },
      children: [
        if (value == null)
          NetworkLoading(error: hidden.error, onRetry: () => ref.invalidate(hiddenAccountsProvider))
        else ...[
          group('Comptes bloqués', value.blocked, blocked: true),
          SizedBox(height: layout.sectionGap),
          group('Masqués du fil', value.muted, blocked: false),
        ],
      ],
    );
  }
}

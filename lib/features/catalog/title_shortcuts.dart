import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../network/network.dart';
import '../profiles/avatars.dart';
import '../social/profile_view.dart' show AccountTile, ProfileHeader;
import 'catalog_repository.dart';
import 'models.dart';
import 'where_to_watch.dart';

class TitleShortcuts extends ConsumerWidget {
  const TitleShortcuts({super.key, required this.title});
  final TitleDetails title;

  String _location(String section) => '/titre/${title.type.name}/${title.id}/$section?titre=${Uri.encodeComponent(title.title)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final social = ref.watch(titleSocialProvider((type: title.type, id: title.id))).value;
    final providers = ref.watch(titleProvidersPreviewProvider((title.type, title.id)));
    final data = providers.valueOrNull ?? const <String, dynamic>{};
    final providerList = [
      ...(data['flatrate'] as List? ?? const []),
      ...(data['free'] as List? ?? const []),
      ...(data['ads'] as List? ?? const []),
      ...(data['rent'] as List? ?? const []),
      ...(data['buy'] as List? ?? const []),
    ].whereType<Map<String, dynamic>>().take(4).toList();
    final friends = social?.friends.take(4).toList() ?? const [];
    final count = social?.reviewsCount ?? 0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VxColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(layout.size(16, tv: 22)),
          border: Border.all(color: VxColors.line),
        ),
        child: Column(children: [
          _ShortcutRow(label: 'Où regarder',
            preview: providers.isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : _ProviderIcons(items: providerList),
            onTap: () => context.push(_location('ou-regarder'))),
          _ShortcutRow(label: 'Voir la bande-annonce',
            preview: const Icon(Icons.smart_display_rounded, color: Color(0xFFFF3333), size: 25),
            onTap: () => context.push(_location('bandes-annonces'))),
          _ShortcutRow(label: 'Commentaires',
            preview: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.mode_comment_outlined, color: VxColors.textSoft, size: 19),
              const SizedBox(width: 6),
              Text('$count', style: VxText.body(layout.captionSize, color: VxColors.textSecondary, weight: FontWeight.w700)),
            ]),
            onTap: () => context.push('/titre/${title.type.name}/${title.id}/avis?titre=${Uri.encodeComponent(title.title)}')),
          _ShortcutRow(label: 'Vu par',
            preview: Row(mainAxisSize: MainAxisSize.min, children: [
              if (friends.isEmpty)
                Text(social == null ? '—' : '0', style: VxText.body(layout.captionSize, color: VxColors.textSecondary))
              else
                for (final friend in friends)
                  Padding(padding: const EdgeInsets.only(left: 4), child: AvatarTile(
                    avatarId: friend.profile.avatar, photoUrl: friend.profile.photoUrl,
                    initial: ProfileHeader.initialOf(friend.profile.name),
                    size: layout.size(28, tv: 40), radius: layout.size(14, tv: 20))),
            ]),
            onTap: () => context.push(_location('vus'))),
        ]),
      ),
    );
  }
}

final titleProvidersPreviewProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (MediaType, int)>(
  (ref, key) => ref.read(catalogRepositoryProvider).watchProviders(key.$1, key.$2, country: 'FR'),
);

class _ProviderIcons extends StatelessWidget {
  const _ProviderIcons({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    for (final item in items)
      Padding(padding: const EdgeInsets.only(left: 4), child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 28, height: 28,
          child: item['logo_path'] is String
              ? Image.network('https://image.tmdb.org/t/p/w92${item['logo_path']}', fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.tv_rounded, size: 20))
              : const Icon(Icons.tv_rounded, size: 20))),
      ),
  ]);
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.preview, required this.onTap});
  final String label;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return VxFocusable(
      borderRadius: 12, onPressed: onTap, semanticLabel: label,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.m), vertical: layout.space(VxSpace.s)),
        child: Row(children: [
          Expanded(child: Text(label, style: VxText.body(layout.bodySize, weight: FontWeight.w600))),
          preview,
          SizedBox(width: layout.space(VxSpace.s)),
          Icon(Icons.chevron_right_rounded, color: VxColors.textSoft, size: layout.size(22, tv: 30)),
        ]),
      ),
    );
  }
}

enum TitleInfoSection { providers, trailers, watchedBy }

class TitleInfoScreen extends ConsumerWidget {
  const TitleInfoScreen({super.key, required this.type, required this.id, required this.section});
  final MediaType type;
  final int id;
  final TitleInfoSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = switch (section) {
      TitleInfoSection.providers => 'Où regarder',
      TitleInfoSection.trailers => 'Bandes-annonces',
      TitleInfoSection.watchedBy => 'Vu par',
    };
    final layout = Layout.of(context);
    final social = ref.watch(titleSocialProvider((type: type, id: id)));
    final details = ref.watch(titleProvider((type, id)));
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.m), layout.gutter, pageBottomPadding(context)),
        children: [
          if (section == TitleInfoSection.providers) WhereToWatchSection(type: type, id: id),
          if (section == TitleInfoSection.trailers)
            AsyncView(value: details, data: (value) => Column(children: [
              for (final trailer in value.trailers)
                ListTile(
                  leading: const Icon(Icons.smart_display_rounded, color: Color(0xFFFF3333)),
                  title: Text(trailer.name?.isNotEmpty == true ? trailer.name! : trailer.kind),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => launchUrl(Uri.parse(trailer.url), mode: LaunchMode.externalApplication)),
            ])),
          if (section == TitleInfoSection.watchedBy)
            AsyncView(value: social, data: (value) => value.friends.isEmpty
                ? const Center(child: Text('Aucun abonnement ne l’a encore vu.'))
                : Column(children: [
                    for (final friend in value.friends)
                      ListTile(
                        leading: AvatarTile(avatarId: friend.profile.avatar, photoUrl: friend.profile.photoUrl,
                          initial: ProfileHeader.initialOf(friend.profile.name), size: 44, radius: 22),
                        title: Text(friend.profile.name),
                        subtitle: Text(friend.rating == null ? 'Vu' : 'Note : ${friend.rating}/10'),
                        onTap: () => context.push(AccountTile.location(friend.profile.username))),
                  ])),
        ],
      ),
    );
  }
}

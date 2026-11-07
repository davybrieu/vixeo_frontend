import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import 'channel_search.dart';
import 'models.dart';
import 'tv_repository.dart';

/// A few live channels for the home row (keeps the request light).
const _homeChannelLimit = 24;

final homeChannelsProvider = FutureProvider.autoDispose<List<TvChannel>>((ref) async {
  final list = await ref.watch(tvRepositoryProvider).channels();
  if (list.length <= _homeChannelLimit) return list;
  return list.take(_homeChannelLimit).toList();
});

/// Horizontal row of live channel tiles (home "Chaînes TV").
class ChannelRow extends ConsumerWidget {
  const ChannelRow({
    super.key,
    required this.channels,
    this.title = 'Chaînes TV',
    this.onSeeAll,
  });

  final List<TvChannel> channels;
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (channels.isEmpty) return const SizedBox.shrink();

    final layout = Layout.of(context);
    final tileSize = layout.isLarge ? layout.tv(140).clamp(96, 160).toDouble() : 96.0;
    final gap = layout.isLarge ? layout.tv(20) : 10.0;
    final vPad = layout.isLarge ? layout.tv(12) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.isLarge ? layout.tv(22) : 12),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: VxText.title(layout.isLarge ? layout.tv(30) : 18)),
              ),
              VxFocusable(
                borderRadius: 8,
                semanticLabel: 'Voir toutes les chaînes TV',
                onPressed: onSeeAll ?? () => context.go('/tv-live'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Voir tout',
                        style: VxText.body(
                          layout.isLarge ? layout.tv(20) : 13,
                          color: VxColors.accent,
                          weight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: layout.isLarge ? layout.tv(6) : 3),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: layout.isLarge ? layout.tv(24) : 18,
                        color: VxColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        FocusTraversalGroup(
          child: SizedBox(
            height: tileSize + 36 + vPad * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
              itemCount: channels.length,
              separatorBuilder: (_, __) => SizedBox(width: gap),
              itemBuilder: (context, i) {
                final channel = channels[i];
                return _ChannelTile(
                  channel: channel,
                  size: tileSize,
                  onTap: () => playLiveChannel(context, ref, channel),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.size,
    required this.onTap,
  });

  final TvChannel channel;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.14;
    return VxFocusable(
      borderRadius: radius,
      semanticLabel: channel.name,
      onPressed: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: ColoredBox(
                color: VxColors.surface,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: channel.logo != null && channel.logo!.isNotEmpty
                      ? Padding(
                          padding: EdgeInsets.all(size * 0.12),
                          child: Image.network(
                            channel.logo!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.live_tv, size: size * 0.4),
                          ),
                        )
                      : Icon(Icons.live_tv, size: size * 0.4, color: VxColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              channel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: VxText.body(12, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
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

/// Horizontal row of live channel tiles (home and search « Chaînes TV »).
class ChannelRow extends ConsumerWidget {
  const ChannelRow({super.key, required this.channels, this.title = 'Chaînes TV'});

  final List<TvChannel> channels;
  final String title;

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
        // No « Voir tout »: all the channels are in the search page (« Chaînes TV »).
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.isLarge ? layout.tv(22) : 12),
          child: Text(title, style: VxText.title(layout.isLarge ? layout.tv(30) : 18)),
        ),
        FocusTraversalGroup(
          child: SizedBox(
            // The tile, then its name on up to two lines (12 px, line height 1.45).
            height: tileSize + 8 + 36 + vPad * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
              itemCount: channels.length,
              separatorBuilder: (_, _) => SizedBox(width: gap),
              itemBuilder: (context, i) {
                final channel = channels[i];
                return ChannelTile(
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

/// A live channel: its logo in a square, its name under it. A press plays it.
class ChannelTile extends StatelessWidget {
  const ChannelTile({super.key, required this.channel, required this.size, required this.onTap});

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
                            errorBuilder: (_, _, _) => Icon(Icons.live_tv, size: size * 0.4),
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

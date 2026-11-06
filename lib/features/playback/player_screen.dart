import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'playback.dart';

class StreamSource {
  const StreamSource({required this.provider, required this.name, required this.url});

  factory StreamSource.fromJson(Map<String, dynamic> json) => StreamSource(
        provider: json['provider'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  final String provider;
  final String name;
  final String url;
}

final streamSourcesProvider = FutureProvider.family<List<StreamSource>, PlaybackItem>((ref, item) async {
  final api = ref.read(apiClientProvider);
  final path = item.type == MediaType.movie
      ? '/catalog/movie/${item.id}/sources'
      : '/catalog/tv/${item.id}/season/${item.season}/episode/${item.episode}/sources';
  final json = await api.get(path);
  final data = json['data'];
  return data is List
      ? data.whereType<Map<String, dynamic>>().map(StreamSource.fromJson).toList()
      : const [];
});

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({
    super.key,
    required this.type,
    required this.id,
    this.season,
    this.episode,
  });

  final MediaType type;
  final int id;
  final int? season;
  final int? episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = (type: type, id: id, season: season, episode: episode);
    final sources = ref.watch(streamSourcesProvider(item));

    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: AsyncView(
        value: sources,
        onRetry: () => ref.invalidate(streamSourcesProvider(item)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Aucune source disponible',
              message: 'Aucun lecteur trouvé pour ce contenu.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = list[i];
              return VxButton(
                label: '${s.provider} — ${s.name}',
                icon: Icons.play_arrow_rounded,
                expand: true,
                onPressed: () async {
                  final ok = await launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
                  if (!ok && context.mounted) {
                    showVxSnack(context, 'Impossible d’ouvrir le lien.');
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

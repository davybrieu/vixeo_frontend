import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'social_repository.dart';

class SocialSearchResults extends ConsumerWidget {
  const SocialSearchResults({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().length < 2) return const SizedBox.shrink();
    final result = ref.watch(socialSearchProvider(query.trim()));
    return result.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Padding(padding: EdgeInsets.all(16), child: Text('Impossible de rechercher les comptes.')),
      data: (profiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8), child: Text('Comptes', style: VxText.title(19))),
        if (profiles.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Aucun compte trouvé.')),
        for (final profile in profiles)
          ListTile(
            leading: CircleAvatar(child: Text(profile.name.isEmpty ? '?' : profile.name[0].toUpperCase())),
            title: Text('@${profile.username}'),
            subtitle: Text('${profile.followersCount} abonnés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/membre/${Uri.encodeComponent(profile.username)}'),
          ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/theme.dart';
import '../auth/session.dart';
import '../auth/auth_repository.dart';
import '../profiles/avatars.dart';
import 'social_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    if (profile == null) {
      return Scaffold(body: Center(child: TextButton(
        onPressed: () => context.go('/profils'),
        child: const Text('Choisir un profil'),
      )));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil'), actions: [
        IconButton(tooltip: 'Modifier mon profil', onPressed: () => context.push('/profil/social/edition'), icon: const Icon(Icons.edit_outlined)),
      ]),
      body: FutureBuilder<SocialProfile>(
        future: ref.read(socialRepositoryProvider).profile(profile.username ?? ''),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Impossible de charger le profil.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final social = snapshot.data!;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              AvatarTile(avatarId: profile.avatar, initial: profile.initial, size: 88, radius: 44),
              const SizedBox(width: 18),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('@${social.username}', style: VxText.title(22)),
                Text(social.name, style: VxText.body(14, color: VxColors.textSecondary)),
              ])),
            ]),
            const SizedBox(height: 18),
            Text(social.bio?.isNotEmpty == true ? social.bio! : 'Ajoutez une biographie pour vous présenter.', style: VxText.body(15)),
            const SizedBox(height: 20),
            Row(children: [
              _Count(label: 'Abonnés', count: social.followersCount),
              const SizedBox(width: 28),
              _Count(label: 'Abonnements', count: social.followingCount),
            ]),
            const SizedBox(height: 24),
            const Divider(),
            ListTile(leading: const Icon(Icons.star_outline), title: const Text('Mes avis'), onTap: () => context.push('/profil/social/avis')),
            ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('Ma liste'), onTap: () => context.push('/profil/social/liste')),
            ListTile(leading: const Icon(Icons.people_outline), title: const Text('Mes abonnements'), onTap: () => context.push('/profil/social/abonnements')),
            ListTile(leading: const Icon(Icons.group_outlined), title: const Text('Mes abonnés'), onTap: () => context.push('/profil/social/abonnes')),
            ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Paramètres'), onTap: () => context.go('/parametres')),
          ]);
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('$count', style: VxText.title(20)),
    Text(label, style: VxText.body(13, color: VxColors.textSecondary)),
  ]);
}

class SocialProfileEditScreen extends ConsumerStatefulWidget {
  const SocialProfileEditScreen({super.key});
  @override
  ConsumerState<SocialProfileEditScreen> createState() => _SocialProfileEditScreenState();
}

class _SocialProfileEditScreenState extends ConsumerState<SocialProfileEditScreen> {
  final _username = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _username.dispose(); _bio.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sessionProvider).profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: FutureBuilder<SocialProfile>(
        future: active == null ? null : ref.read(socialRepositoryProvider).profile(active.username ?? ''),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final social = snapshot.data!;
          if (_username.text.isEmpty) _username.text = social.username;
          if (_bio.text.isEmpty) _bio.text = social.bio ?? '';
          return ListView(padding: const EdgeInsets.all(20), children: [
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Pseudo', prefixText: '@', helperText: '3 à 30 caractères, lettres, chiffres et _')),
            const SizedBox(height: 16),
            TextField(controller: _bio, maxLength: 500, maxLines: 5, decoration: const InputDecoration(labelText: 'Biographie')),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : () async {
                setState(() { _loading = true; _error = null; });
                try {
                  final updated = await ref.read(authRepositoryProvider).updateProfile(active!.id, {'username': _username.text.trim(), 'bio': _bio.text.trim()});
                  ref.read(sessionProvider.notifier).updateProfile(updated);
                  if (context.mounted) context.pop();
                } catch (e) { if (mounted) setState(() => _error = e.toString()); }
                finally { if (mounted) setState(() => _loading = false); }
              },
              child: Text(_loading ? 'Enregistrement…' : 'Enregistrer'),
            ),
          ]);
        },
      ),
    );
  }
}


class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.username});
  final String username;
  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  late Future<SocialProfile> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(socialRepositoryProvider).profile(widget.username);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profil')),
    body: FutureBuilder<SocialProfile>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Profil introuvable.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final profile = snapshot.data!;
        return ListView(padding: const EdgeInsets.all(20), children: [
          CircleAvatar(radius: 44, child: Text(profile.name.isEmpty ? '?' : profile.name[0].toUpperCase())),
          const SizedBox(height: 12),
          Center(child: Text('@${profile.username}', style: VxText.title(22))),
          Center(child: Text(profile.name, style: VxText.body(14, color: VxColors.textSecondary))),
          const SizedBox(height: 16),
          Text(profile.bio ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Count(label: 'Abonnés', count: profile.followersCount),
            const SizedBox(width: 32),
            _Count(label: 'Abonnements', count: profile.followingCount),
          ]),
          const SizedBox(height: 20),
          if (!profile.isSelf)
            FilledButton(
              onPressed: _busy ? null : () async {
                setState(() => _busy = true);
                try {
                  if (profile.isFollowing) {
                    await ref.read(socialRepositoryProvider).unfollow(profile.username);
                  } else {
                    await ref.read(socialRepositoryProvider).follow(profile.username);
                  }
                  setState(() => _future = ref.read(socialRepositoryProvider).profile(profile.username));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              child: Text(_busy ? 'Patientez…' : profile.isFollowing ? 'Ne plus suivre' : 'Suivre'),
            ),
          const Divider(height: 32),
          ListTile(leading: const Icon(Icons.star_outline), title: const Text('Avis')),
          ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('Ma liste')),
        ]);
      },
    ),
  );
}


class SocialCollectionScreen extends ConsumerWidget {
  const SocialCollectionScreen({super.key, required this.section, this.username});
  final String section;
  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(sessionProvider).profile;
    final handle = username ?? active?.username;
    final titles = {
      'avis': 'Avis', 'reviews': 'Avis', 'liste': 'Ma liste', 'list': 'Ma liste',
      'abonnes': 'Abonnés', 'followers': 'Abonnés',
      'abonnements': 'Abonnements', 'following': 'Abonnements',
    };
    final endpoint = switch (section) {
      'avis' || 'reviews' => 'reviews',
      'liste' || 'list' => 'list',
      'abonnes' || 'followers' => 'followers',
      _ => 'following',
    };
    return Scaffold(
      appBar: AppBar(title: Text(titles[section] ?? 'Profil')),
      body: handle == null
          ? const Center(child: Text('Aucun profil sélectionné.'))
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: ref.read(socialRepositoryProvider).collection(handle, endpoint),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Impossible de charger cette rubrique.'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final items = snapshot.data!;
                if (items.isEmpty) return const Center(child: Text('Aucun élément à afficher.'));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final title = item['title'] as String? ?? item['name'] as String? ?? item['username'] as String? ?? 'Contenu';
                    final subtitle = endpoint == 'reviews'
                        ? 'Note : ${item['value'] ?? '—'} / 10 · ${item['comment'] ?? ''}'
                        : endpoint == 'followers' || endpoint == 'following'
                            ? '@${item['username'] ?? ''}'
                            : item['year']?.toString() ?? '';
                    return ListTile(
                      leading: CircleAvatar(child: Text(title.isEmpty ? '?' : title[0].toUpperCase())),
                      title: Text(title),
                      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: (endpoint == 'followers' || endpoint == 'following') && item['username'] != null
                          ? () => context.push('/membre/${Uri.encodeComponent(item['username'] as String)}')
                          : null,
                    );
                  },
                );
              },
            ),
    );
  }
}

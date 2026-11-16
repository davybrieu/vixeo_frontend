import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../library/library.dart';
import '../profiles/avatars.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'social_repository.dart';

/// « Profil » (tab): the active profile's page. At the top, its avatar, name, @username, followers
/// and following, bio and « Modifier le profil »; then its counters (reviews, watched, list) and
/// its activity: « Ma liste » (a row of posters) and « Mes avis » (the latest reviews). The round
/// arrow of each section opens the whole list or every review.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Latest reviews on the page; the others are on « Mes avis ».
  static const reviewsShown = 3;

  /// Titles of « Ma liste » in the row (the most recently added).
  static const listShown = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    if (profile == null) {
      return EmptyState(
        icon: Icons.person_outline_rounded,
        title: 'Aucun profil choisi',
        message: 'Choisissez un profil pour voir sa page.',
        action: VxButton(label: 'Choisir un profil', autofocus: true, onPressed: () => context.go('/profils')),
      );
    }
    if (profile.isKid) {
      return const EmptyState(
        icon: Icons.child_care_rounded,
        title: 'Pas de page de profil',
        message: 'Les profils enfants ne disposent pas de profil public.',
      );
    }

    final layout = Layout.of(context);
    final username = profile.username?.trim() ?? '';
    final social = username.isEmpty ? null : ref.watch(socialProfileProvider(username)).value;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          if (username.isNotEmpty) ref.invalidate(socialProfileProvider(username));
          ref.invalidate(reviewsProvider);
          await ref.read(libraryProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: layout.space(VxSpace.m), bottom: pageBottomPadding(context)),
          children: [
            _ReadingColumn(child: _Header(profile: profile, social: social)),
            SizedBox(height: layout.sectionGap),
            _ReadingColumn(child: _Counters(social: social)),
            SizedBox(height: layout.sectionGap),
            const _MyList(),
            SizedBox(height: layout.sectionGap),
            const _MyReviews(),
          ],
        ),
      ),
    );
  }
}

/// The page's reading column: page margins, 900 wide at most (TV 1500), on the left.
class _ReadingColumn extends StatelessWidget {
  const _ReadingColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.size(900, tv: 1500)),
          child: child,
        ),
      ),
    );
  }
}

/// Avatar, name, @username, followers and following, bio, then « Modifier le profil ».
class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.social});

  final Profile profile;

  /// The public page (followers, following), null while it loads or without a username.
  final SocialProfile? social;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(88, tv: 160);
    final username = profile.username?.trim() ?? '';
    final bio = (profile.bio ?? social?.bio ?? '').trim();
    final followers = social?.followersCount;
    final following = social?.followingCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProfileAvatar(profile: profile, size: avatar, radius: avatar / 2),
            SizedBox(width: layout.space(VxSpace.m)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.title(layout.size(24, tv: 48)),
                  ),
                  if (username.isNotEmpty) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
                    ),
                  ],
                  if (followers != null && following != null) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    Wrap(
                      spacing: layout.space(VxSpace.m),
                      children: [
                        _FollowLink(
                          count: followers,
                          one: 'abonné',
                          many: 'abonnés',
                          location: '/profil/social/abonnes',
                        ),
                        _FollowLink(
                          count: following,
                          one: 'abonnement',
                          many: 'abonnements',
                          location: '/profil/social/abonnements',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        Text(
          bio.isEmpty ? 'Ajoutez une biographie pour vous présenter.' : bio,
          style: VxText.body(layout.bodySize, color: bio.isEmpty ? VxColors.textMuted : VxColors.textSoft),
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        VxButton(
          label: username.isEmpty ? 'Choisir un pseudo' : 'Modifier le profil',
          icon: Icons.edit_outlined,
          kind: VxButtonKind.secondary,
          dense: true,
          // The page's first element: the focus on arrival (TV).
          autofocus: true,
          onPressed: () => context.push('/profil/social/edition'),
        ),
      ],
    );
  }
}

/// "12 abonnés": opens the list of followers (or of followed profiles).
class _FollowLink extends StatelessWidget {
  const _FollowLink({required this.count, required this.one, required this.many, required this.location});

  final int count;
  final String one;
  final String many;
  final String location;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.bodySize;
    // French: "0 abonné", "1 abonné", "2 abonnés".
    final word = count > 1 ? many : one;
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: '$count $word',
      onPressed: () => context.push(location),
      child: ConstrainedBox(
        // A touch target of 44 at least.
        constraints: BoxConstraints(minHeight: layout.size(44, tv: 60)),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$count ', style: VxText.body(size, weight: FontWeight.w700)),
                TextSpan(text: word, style: VxText.body(size, color: VxColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reviews, watched titles and titles in « Ma liste », side by side in a card. The list and the
/// reviews are counted from what the page shows (up to date at once), the rest by the API.
class _Counters extends ConsumerWidget {
  const _Counters({required this.social});

  final SocialProfile? social;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final favorites = ref.watch(libraryProvider).value?.favorites;
    final reviews = ref.watch(canRateProvider) ? ref.watch(reviewsProvider).value : null;
    final divider = Container(width: 1, height: layout.size(36, tv: 64), color: VxColors.line);

    return VxCard(
      padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.m), horizontal: layout.space(VxSpace.xs)),
      child: Row(
        children: [
          Expanded(child: _Counter(value: reviews?.length ?? social?.reviewsCount, label: 'Avis')),
          divider,
          Expanded(child: _Counter(value: social?.watchedCount, label: 'Vus')),
          divider,
          Expanded(
            child: _Counter(
              value: favorites == null ? social?.listCount : favoriteTitles(favorites).length,
              label: 'Ma liste',
            ),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.label});

  /// Null while it loads: a dash.
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Semantics(
      container: true,
      label: '$label : ${value ?? 'chargement'}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value?.toString() ?? '–',
            maxLines: 1,
            style: VxText.title(layout.size(22, tv: 44)),
          ),
          SizedBox(height: layout.space(VxSpace.xxs)),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The movies and series of « Ma liste », once each (an episode in the list counts for its series),
/// the most recently added first.
List<({ProfileItem favorite, TitleRef title})> favoriteTitles(List<ProfileItem> favorites) {
  final seen = <TitleRef>{};
  return [
    for (final favorite in favorites)
      if (favorite.tmdbTitle case final t?)
        if (seen.add(t)) (favorite: favorite, title: t),
  ];
}

/// « Ma liste »: a row of posters, as on the home page; the arrow opens the whole list.
class _MyList extends ConsumerWidget {
  const _MyList();

  static const title = 'Ma liste';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final format = posterFormatOf(ref);
    final width = rowCardWidth(layout, format);
    final rowHeight =
        PosterCard.heightFor(width, format) +
        PosterCard.captionHeightOf(context) +
        (layout.isLarge ? layout.tv(16) * 2 : 0);
    void seeAll() => context.push('/ma-liste');

    final library = ref.watch(libraryProvider);
    final state = library.value;
    if (state == null) {
      return library.hasError
          ? const _SectionMessage(title: title, message: 'Impossible de charger votre liste.')
          : _SectionLoading(title: title, height: rowHeight);
    }
    final favorites = favoriteTitles(state.favorites).take(ProfileScreen.listShown).toList();
    if (favorites.isEmpty) {
      return const _SectionMessage(
        title: title,
        message: 'Ajoutez des films et des séries avec « Ma liste » : ils apparaîtront ici.',
      );
    }

    // Every title of the row in one request (poster, rating, logo): never one per card.
    final batch = ref.watch(titlesByIdProvider(titlesKey(favorites.map((f) => f.title))));
    if (!batch.hasValue && batch.isLoading) return _SectionLoading(title: title, height: rowHeight);
    final known = batch.value ?? const <TitleRef, MediaItem>{};

    return PosterRow(
      title: title,
      onSeeAll: seeAll,
      items: [for (final f in favorites) _item(f.favorite, f.title, known[f.title])],
    );
  }

  /// A title of the list, completed by the catalog (rating, logo, summary) once read.
  static MediaItem _item(ProfileItem favorite, TitleRef id, MediaItem? details) => MediaItem(
    id: id.id,
    type: id.type,
    title: favorite.title,
    year: details?.year ?? favorite.year,
    voteAverage: details?.voteAverage ?? 0,
    posterUrl: favorite.posterUrl ?? details?.posterUrl,
    backdropUrl: favorite.backdropUrl ?? details?.backdropUrl,
    logoUrl: details?.logoUrl,
    logoAspectRatio: details?.logoAspectRatio,
    summary: details?.summary,
  );
}

/// « Mes avis »: the latest reviews (the same rows as the « Mes avis » page); the arrow opens them
/// all. Without a TMDb account, an invitation to link one.
class _MyReviews extends ConsumerWidget {
  const _MyReviews();

  static const title = 'Mes avis';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final loadingHeight = layout.size(96, tv: 160);
    final account = ref.watch(tmdbAccountProvider);

    if (account.value?.linked != true) {
      if (account.isLoading) return _SectionLoading(title: title, height: loadingHeight);
      return _SectionMessage(
        title: title,
        message: 'Liez votre compte TMDb pour noter les films, les séries et les épisodes.',
        action: VxButton(
          label: 'Lier mon compte TMDb',
          icon: Icons.link_rounded,
          kind: VxButtonKind.outline,
          dense: true,
          onPressed: () => context.push('/profil/connexions'),
        ),
      );
    }

    final reviews = ref.watch(reviewsProvider);
    final all = reviews.value;
    if (all == null) {
      return reviews.hasError
          ? const _SectionMessage(title: title, message: 'Impossible de charger vos avis.')
          : _SectionLoading(title: title, height: loadingHeight);
    }
    if (all.isEmpty) {
      return const _SectionMessage(
        title: title,
        message: 'Notez un film, une série ou un épisode depuis sa fiche : votre avis apparaîtra ici.',
      );
    }

    final latest = all.take(ProfileScreen.reviewsShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, onSeeAll: () => context.push('/avis')),
        _ReadingColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, item) in latest.indexed) ...[
                if (i > 0) SizedBox(height: layout.listGap),
                ReviewRow(item: item),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A section without anything to show yet: its title and a sentence (and a button, if an action
/// exists).
class _SectionMessage extends StatelessWidget {
  const _SectionMessage({required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        _ReadingColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: VxText.body(layout.bodySize, color: VxColors.textSecondary)),
              if (action != null) ...[SizedBox(height: layout.space(VxSpace.s)), action!],
            ],
          ),
        ),
      ],
    );
  }
}

/// A section while it loads: its title and the room of its content (nothing moves when it comes).
class _SectionLoading extends StatelessWidget {
  const _SectionLoading({required this.title, required this.height});

  final String title;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title),
      SizedBox(height: height, child: const Center(child: CircularProgressIndicator())),
    ],
  );
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
                  // The « Profil » page reads its followers and counters again (new username…).
                  ref.invalidate(socialProfileProvider);
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
              child: Text(_busy ? 'Patientez…' : ref.watch(sessionProvider).isSignedIn ? (profile.isFollowing ? 'Ne plus suivre' : 'Suivre') : 'Se connecter pour suivre'),
            ),
          const Divider(height: 32),
          ListTile(leading: const Icon(Icons.star_outline), title: const Text('Avis'), onTap: () => context.push('/membre/${Uri.encodeComponent(profile.username)}/reviews')),
          ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('Ma liste'), onTap: () => context.push('/membre/${Uri.encodeComponent(profile.username)}/list')),
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

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$count', style: VxText.title(20)),
      Text(label, style: VxText.body(13, color: VxColors.textSecondary)),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../library/library.dart';
import '../library/my_list_screen.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'profile_view.dart';
import 'social_repository.dart';

/// « Profil » (tab): the active profile's page (`ProfileView`). At the top, its avatar, name,
/// @username, followers and following, bio and « Modifier le profil »; then its counters and its
/// activity: « Ma liste » (a row of posters) and « Mes avis » (the latest reviews). The round arrow
/// of each section opens the whole list or every review.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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

    // « Ma liste » and « Mes avis » from what this device keeps up to date (a change shows at once).
    final library = ref.watch(libraryProvider);
    final favorites = library.value == null ? null : favoriteTitles(library.value!.favorites);
    final AsyncValue<List<MediaItem>> titles;
    if (favorites == null) {
      titles = library.hasError
          ? AsyncError<List<MediaItem>>(library.error!, StackTrace.empty)
          : const AsyncLoading<List<MediaItem>>();
    } else {
      titles = withCatalogDetails(ref, [
            for (final (:favorite, :title) in favorites.take(profileTitlesShown))
              MediaItem(
                id: title.id,
                type: title.type,
                title: favorite.title,
                year: favorite.year,
                posterUrl: favorite.posterUrl,
                backdropUrl: favorite.backdropUrl,
              ),
          ]);
    }
    final account = ref.watch(tmdbAccountProvider);
    final linked = account.value?.linked == true;
    final reviews = linked ? ref.watch(reviewsProvider) : null;

    const reviewsTitle = 'Mes avis';
    final Widget reviewsSection;
    if (reviews != null) {
      reviewsSection = ProfileReviewsSection(
        title: reviewsTitle,
        reviews: reviews,
        mine: true,
        emptyMessage: 'Notez un film, une série ou un épisode depuis sa fiche : votre avis apparaîtra ici.',
        onSeeAll: () => context.push('/avis'),
      );
    } else if (account.isLoading) {
      reviewsSection = ProfileSectionLoading(title: reviewsTitle, height: layout.size(96, tv: 160));
    } else {
      reviewsSection = ProfileSectionMessage(
        title: reviewsTitle,
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

    return ProfileView(
      onRefresh: () async {
        if (username.isNotEmpty) ref.invalidate(socialProfileProvider(username));
        ref.invalidate(reviewsProvider);
        await ref.read(libraryProvider.notifier).refresh();
      },
      header: ProfileHeader(
        name: profile.name,
        avatarId: profile.avatar,
        username: username,
        bio: profile.bio ?? social?.bio,
        emptyBio: 'Ajoutez une biographie pour vous présenter.',
        followers: social?.followersCount,
        following: social?.followingCount,
        onFollowers: () => context.push('/profil/social/abonnes'),
        onFollowing: () => context.push('/profil/social/abonnements'),
        action: VxButton(
          label: username.isEmpty ? 'Choisir un pseudo' : 'Modifier le profil',
          icon: Icons.edit_outlined,
          kind: VxButtonKind.secondary,
          dense: true,
          // The page's first element: the focus on arrival (TV).
          autofocus: true,
          onPressed: () => context.push('/profil/social/edition'),
        ),
      ),
      counters: ProfileCounters(
        reviews: linked ? reviews?.value?.length : social?.reviewsCount,
        watched: social?.watchedCount,
        titles: favorites?.length ?? social?.listCount,
      ),
      sections: [
        ProfileTitlesSection(
          title: 'Ma liste',
          titles: titles,
          emptyMessage: 'Ajoutez des films et des séries avec « Ma liste » : ils apparaîtront ici.',
          onSeeAll: () => context.push('/ma-liste'),
        ),
        reviewsSection,
      ],
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

/// A member's page (`/membre/:username`): the same page as mine (`ProfileView`), with their list,
/// their reviews and « Suivre ». My own page opened from a list shows « Modifier le profil ».
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  /// Where a member's list or reviews open: `list`, `reviews`, `followers`, `following`.
  String _section(String section) => '/membre/${Uri.encodeComponent(username)}/$section';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(socialProfileProvider(username));
    final social = profile.value;

    if (social == null) {
      return Scaffold(
        body: SafeArea(
          child: profile.hasError
              ? EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'Profil introuvable',
                  message: 'Ce profil n’existe pas ou n’est pas public.',
                  action: VxButton(
                    label: 'Retour',
                    autofocus: true,
                    onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final titles = ref.watch(socialTitlesProvider(username));
    final reviews = ref.watch(socialReviewsProvider(username));

    return Scaffold(
      body: ProfileView(
        back: true,
        onRefresh: () async {
          ref.invalidate(socialTitlesProvider(username));
          ref.invalidate(socialReviewsProvider(username));
          ref.invalidate(socialProfileProvider(username));
          await ref.read(socialProfileProvider(username).future);
        },
        header: ProfileHeader(
          name: social.name,
          avatarId: social.avatar,
          username: social.username,
          bio: social.bio,
          followers: social.followersCount,
          following: social.followingCount,
          onFollowers: () => context.push(_section('followers')),
          onFollowing: () => context.push(_section('following')),
          action: social.isSelf
              ? VxButton(
                  label: 'Modifier le profil',
                  icon: Icons.edit_outlined,
                  kind: VxButtonKind.secondary,
                  dense: true,
                  autofocus: true,
                  onPressed: () => context.push('/profil/social/edition'),
                )
              : _FollowButton(profile: social),
        ),
        counters: ProfileCounters(
          reviews: social.reviewsCount,
          watched: social.watchedCount,
          titles: social.listCount,
          titlesLabel: 'Sa liste',
        ),
        sections: [
          ProfileTitlesSection(
            title: 'Sa liste',
            titles: switch (titles.value) {
              final list? => withCatalogDetails(ref, list.take(profileTitlesShown).toList()),
              null when titles.hasError => AsyncError<List<MediaItem>>(titles.error!, StackTrace.empty),
              null => const AsyncLoading<List<MediaItem>>(),
            },
            emptyMessage: 'Sa liste est vide pour l’instant.',
            onSeeAll: () => context.push(_section('list')),
          ),
          ProfileReviewsSection(
            title: 'Ses avis',
            reviews: reviews,
            mine: false,
            emptyMessage: 'Aucun avis pour l’instant.',
            onSeeAll: () => context.push(_section('reviews')),
          ),
        ],
      ),
    );
  }
}

/// « Suivre » / « Ne plus suivre » (signed in), or « Se connecter pour suivre » (guest).
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.profile});

  final SocialProfile profile;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final profile = widget.profile;
    final repository = ref.read(socialRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (profile.isFollowing) {
        await repository.unfollow(profile.username);
      } else {
        await repository.follow(profile.username);
      }
      if (!mounted) return;
      ref.invalidate(socialProfileProvider(profile.username));
      showVxSnackOn(
        messenger,
        profile.isFollowing ? 'Vous ne suivez plus @${profile.username}' : 'Vous suivez @${profile.username}',
      );
    } catch (_) {
      showVxSnackOn(messenger, 'Impossible de modifier l’abonnement.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.isSignedIn));
    final following = widget.profile.isFollowing;
    if (!signedIn) {
      return VxButton(
        label: 'Se connecter pour suivre',
        dense: true,
        autofocus: true,
        onPressed: () => context.go(
          '/connexion?redirect=${Uri.encodeComponent(AccountTile.location(widget.profile.username))}',
        ),
      );
    }
    return VxButton(
      label: following ? 'Ne plus suivre' : 'Suivre',
      icon: following ? Icons.person_remove_outlined : Icons.person_add_alt_1_rounded,
      kind: following ? VxButtonKind.secondary : VxButtonKind.primary,
      dense: true,
      autofocus: true,
      loading: _busy,
      onPressed: _toggle,
    );
  }
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
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Pseudo', prefixText: '@')),
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

/// The whole list, reviews, followers or followed profiles of a member (`/membre/:username/list`…)
/// or of the active profile (`/profil/social/abonnes`…). The list and the reviews are the pages of
/// « Ma liste » and « Mes avis » (`MyListScreen`, `ReviewsScreen`: search, filters, order), « Sa
/// liste » and « Ses avis » for a member; followers and followed profiles: back button, title and
/// the members (`AccountTile`).
class SocialCollectionScreen extends ConsumerWidget {
  const SocialCollectionScreen({super.key, required this.section, this.username});

  /// `list` / `liste`, `reviews` / `avis`, `followers` / `abonnes`, `following` / `abonnements`.
  final String section;

  /// Null: the active profile.
  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final active = ref.watch(sessionProvider).profile;
    final handle = username ?? active?.username;
    final mine = handle == null || handle == active?.username;
    final kind = switch (section) {
      'avis' || 'reviews' => _Kind.reviews,
      'liste' || 'list' => _Kind.list,
      'abonnes' || 'followers' => _Kind.followers,
      _ => _Kind.following,
    };
    switch (kind) {
      case _Kind.list:
        return mine ? const MyListScreen() : MyListScreen(username: handle);
      case _Kind.reviews:
        return mine ? const ReviewsScreen() : ReviewsScreen(username: handle);
      case _Kind.followers || _Kind.following:
        break;
    }
    final followers = kind == _Kind.followers;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.m), layout.gutter, 0),
              child: const VxBackButton(),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                layout.gutter,
                layout.space(VxSpace.m),
                layout.gutter,
                layout.space(VxSpace.m),
              ),
              child: Text(followers ? 'Abonnés' : 'Abonnements', style: VxText.title(layout.pageTitleSize)),
            ),
            Expanded(
              child: handle == null || handle.isEmpty
                  ? const EmptyState(icon: Icons.person_outline_rounded, title: 'Aucun profil choisi')
                  : _Async(
                      value: ref.watch(socialConnectionsProvider((username: handle, followers: followers))),
                      empty: followers ? 'Aucun abonné pour l’instant.' : 'Aucun abonnement pour l’instant.',
                      builder: (profiles) => ListView.separated(
                        padding: pageContentPadding(context),
                        itemCount: profiles.length,
                        separatorBuilder: (_, _) => SizedBox(height: layout.listGap),
                        itemBuilder: (_, i) =>
                            ProfileColumn(child: AccountTile(profile: profiles[i], autofocus: i == 0)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { list, reviews, followers, following }

/// [value] loading, failed, empty, or its content.
class _Async<T> extends StatelessWidget {
  const _Async({required this.value, required this.empty, required this.builder});

  final AsyncValue<List<T>> value;
  final String empty;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    final items = value.value;
    if (items == null) {
      return value.hasError
          ? const EmptyState(icon: Icons.error_outline_rounded, title: 'Impossible de charger cette page')
          : const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) return EmptyState(icon: Icons.inbox_outlined, title: empty);
    return builder(items);
  }
}

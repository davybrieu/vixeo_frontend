import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/share.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../library/library.dart';
import '../library/my_list_screen.dart';
import '../profiles/profiles_screen.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'profile_view.dart';
import 'social_repository.dart';

/// « Profil » (tab): the active profile's page (`ProfileView`). At the top, its avatar, name,
/// @username, followers and following, bio and « Modifier le profil »; then its counters and its
/// activity: « Ma liste » and « Favoris » ❤ (rows of posters), « Personnes suivies » (round
/// photos) and « Mes avis » (the latest reviews). The round arrow of each section opens it whole.
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
    // « Favoris » ❤ and « Personnes suivies », from the same synced library.
    final AsyncValue<List<MediaItem>> liked;
    final AsyncValue<List<Person>> people;
    if (library.value case final state?) {
      liked = withCatalogDetails(ref, [
        for (final item in state.liked.take(profileTitlesShown))
          if (item.tmdbTitle case final t?)
            MediaItem(
              id: t.id,
              type: t.type,
              title: item.title,
              year: item.year,
              posterUrl: item.posterUrl,
              backdropUrl: item.backdropUrl,
            ),
      ]);
      people = AsyncData(state.followedPeople);
    } else if (library.hasError) {
      liked = AsyncError<List<MediaItem>>(library.error!, StackTrace.empty);
      people = AsyncError<List<Person>>(library.error!, StackTrace.empty);
    } else {
      liked = const AsyncLoading<List<MediaItem>>();
      people = const AsyncLoading<List<Person>>();
    }
    // « Mes avis ».
    final reviews = ref.watch(reviewsProvider);

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
        onShare: switch (social?.shareUrl) {
          final url? when canShareLinks => () => shareLink(
            ref,
            context,
            url: url,
            message: 'Retrouve-moi sur Vixeo : ${profile.name} (@$username)',
            subject: 'Vixeo',
          ),
          _ => null,
        },
      ),
      counters: ProfileCounters(
        reviews: reviews.value?.length ?? social?.reviewsCount,
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
        ProfileTitlesSection(
          title: 'Favoris',
          titles: liked,
          emptyMessage: 'Ajoutez des films et des séries à vos favoris avec le cœur de leur fiche : ils apparaîtront ici.',
          onSeeAll: () => context.push('/profil/social/favoris'),
        ),
        ProfilePeopleSection(
          title: 'Personnes suivies',
          people: people,
          emptyMessage: 'Suivez des acteurs et des réalisateurs depuis leur page : ils apparaîtront ici.',
          onSeeAll: () => context.push('/profil/social/personnes'),
        ),
        ProfileReviewsSection(
          title: 'Mes avis',
          reviews: reviews,
          mine: true,
          emptyMessage: 'Notez un film, une série ou un épisode depuis sa fiche : votre avis apparaîtra ici.',
          onSeeAll: () => context.push('/avis'),
        ),
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
    final liked = ref.watch(socialLikedProvider(username));
    final people = ref.watch(socialPeopleProvider(username));
    final reviews = ref.watch(socialReviewsProvider(username));

    return Scaffold(
      body: ProfileView(
        back: true,
        onRefresh: () async {
          ref.invalidate(socialTitlesProvider(username));
          ref.invalidate(socialLikedProvider(username));
          ref.invalidate(socialPeopleProvider(username));
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
          onShare: switch (social.shareUrl) {
            final url? when canShareLinks => () => shareLink(
              ref,
              context,
              url: url,
              message: 'Le profil de ${social.name} (@${social.username}) sur Vixeo',
              subject: 'Vixeo',
            ),
            _ => null,
          },
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
          ProfileTitlesSection(
            title: 'Ses favoris',
            titles: switch (liked.value) {
              final list? => withCatalogDetails(ref, list.take(profileTitlesShown).toList()),
              null when liked.hasError => AsyncError<List<MediaItem>>(liked.error!, StackTrace.empty),
              null => const AsyncLoading<List<MediaItem>>(),
            },
            emptyMessage: 'Aucun favori pour l’instant.',
            onSeeAll: () => context.push(_section('liked')),
          ),
          ProfilePeopleSection(
            title: 'Personnes suivies',
            people: people,
            emptyMessage: 'Aucune personne suivie pour l’instant.',
            onSeeAll: () => context.push(_section('people')),
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

  /// Longest biography, in characters (the API's limit too; developer's request, 21/11/2026).
  static const bioMaxLength = 160;

  /// Longest profile name (the API's limit).
  static const nameMaxLength = 50;

  @override
  ConsumerState<SocialProfileEditScreen> createState() => _SocialProfileEditScreenState();
}

/// « Modifier mon profil » (button of the « Profil » page): the profile's name, its @username and
/// its biography (developer's request, 21/11/2026: the name too). Saved by `PUT /profiles/{id}`.
class _SocialProfileEditScreenState extends ConsumerState<SocialProfileEditScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  late final Future<SocialProfile?> _social = _load();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Filled once (not at each build: an emptied field stayed empty).
    final profile = ref.read(sessionProvider).profile;
    _name.text = profile?.name ?? '';
    _username.text = profile?.username ?? '';
    _bio.text = profile?.bio ?? '';
  }

  /// The public profile, for a biography the session doesn't have yet.
  Future<SocialProfile?> _load() async {
    final username = ref.read(sessionProvider).profile?.username ?? '';
    if (username.isEmpty) return null;
    final social = await ref.read(socialRepositoryProvider).profile(username);
    if (mounted && _bio.text.isEmpty) _bio.text = social.bio ?? '';
    return social;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final active = ref.read(sessionProvider).profile;
    if (active == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Le nom du profil est obligatoire.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final updated = await ref.read(authRepositoryProvider).updateProfile(active.id, {
        'name': name,
        'username': _username.text.trim(),
        'bio': _bio.text.trim(),
      });
      ref.read(sessionProvider.notifier).updateProfile(updated);
      // The « Profil » page reads its followers and counters again (new username…), and
      // « Qui regarde ? » shows the new name.
      ref.invalidate(socialProfileProvider);
      ref.invalidate(profilesProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: FutureBuilder<SocialProfile?>(
        future: _social,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _name,
                autofocus: !DeviceInfo.isTv,
                maxLength: SocialProfileEditScreen.nameMaxLength,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nom', counterText: ''),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _username,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Pseudo', prefixText: '@'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bio,
                maxLength: SocialProfileEditScreen.bioMaxLength,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Biographie'),
              ),
              if (_error != null) Text(_error!, style: const TextStyle(color: VxColors.dangerText)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _save,
                child: Text(_loading ? 'Enregistrement…' : 'Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The whole list, favorites, followed people, reviews, followers or followed profiles of a member
/// (`/membre/:username/list`…) or of the active profile (`/profil/social/abonnes`…). The list, the
/// favorites and the reviews are the pages of « Ma liste » and « Mes avis » (`MyListScreen`,
/// `ReviewsScreen`: search, filters, order), « Sa liste », « Ses favoris » and « Ses avis » for a
/// member; followed people: their round photos in a grid; followers and followed profiles: back
/// button, title and the members (`AccountTile`).
class SocialCollectionScreen extends ConsumerWidget {
  const SocialCollectionScreen({super.key, required this.section, this.username});

  /// `list` / `liste`, `liked` / `favoris`, `people` / `personnes`, `reviews` / `avis`, `followers` /
  /// `abonnes`, `following` / `abonnements`.
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
      'favoris' || 'liked' => _Kind.liked,
      'personnes' || 'people' => _Kind.people,
      'abonnes' || 'followers' => _Kind.followers,
      _ => _Kind.following,
    };
    switch (kind) {
      case _Kind.list:
        return mine ? const MyListScreen() : MyListScreen(username: handle);
      case _Kind.liked:
        return mine ? const MyListScreen(liked: true) : MyListScreen(username: handle, liked: true);
      case _Kind.reviews:
        return mine ? const ReviewsScreen() : ReviewsScreen(username: handle);
      case _Kind.people:
        return _PeopleScreen(username: mine ? null : handle);
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

enum _Kind { list, liked, people, reviews, followers, following }

/// « Personnes suivies » (mine: [username] null) or a member's: back button, title and their round
/// photos in a grid; a photo opens the person's page.
class _PeopleScreen extends ConsumerWidget {
  const _PeopleScreen({this.username});

  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final member = username;
    final AsyncValue<List<Person>> people = member == null
        ? ref.watch(libraryProvider).whenData((state) => state.followedPeople)
        : ref.watch(socialPeopleProvider(member));
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
              child: Text('Personnes suivies', style: VxText.title(layout.pageTitleSize)),
            ),
            Expanded(
              child: _Async(
                value: people,
                empty: member == null
                    ? 'Vous ne suivez personne pour l’instant.'
                    : 'Aucune personne suivie pour l’instant.',
                builder: (all) => GridView.builder(
                  padding: pageContentPadding(context),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: PersonCard.widthOf(layout) + layout.cardGap,
                    mainAxisExtent: PersonCard.heightOf(layout, withRole: false) + layout.cardGap,
                  ),
                  itemCount: all.length,
                  itemBuilder: (_, i) => Center(child: PersonCard(person: all[i])),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

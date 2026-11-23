import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/share.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../library/library.dart';
import '../library/my_list_screen.dart';
import '../messages/messages.dart' show conversationLocation, startConversation;
import '../network/actions.dart' show showMemberMenu;
import '../network/network.dart' show activityProvider, memberListsProvider, myListsProvider;
import '../network/profile_sections.dart';
import '../notifications/inbox.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'profile_view.dart';
import 'social_repository.dart';

/// « Profil » (tab): the active profile's page (`ProfileView`). At the top right « Partager le
/// profil » and, on a phone, « Paramètres »; then its avatar, name, @username, followers and
/// following, bio and networks (changed in « Paramètres » : no « Modifier le profil » button, nor
/// « Mes 4 favoris »: developer's request, 23/11/2026); then its counters and five tabs:
/// « Activité » (each action with its date), « Listes » (« À voir » first, then my lists),
/// « Avis », « Aimés » (titles liked and followed people) and « Vus » (titles watched, « Mon
/// année »). An empty tab shows the [EmptyState] of the « Fil d'actualité ». The round arrow of a
/// section opens it whole.
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

    // « À voir », « J'aime » ❤, « Vus » and « Personnes suivies » from what this device keeps up to
    // date (a change shows at once).
    final library = ref.watch(libraryProvider);
    AsyncValue<List<MediaItem>> titles(List<MediaItem> Function(LibraryState state) of) => switch (library) {
      AsyncValue(:final value?) => withCatalogDetails(ref, of(value).take(profileGridShown).toList()),
      AsyncValue(:final error?) => AsyncError<List<MediaItem>>(error, StackTrace.empty),
      _ => const AsyncLoading<List<MediaItem>>(),
    };
    final liked = titles((state) => [for (final item in state.liked) ?item.asMediaItem]);
    final watched = titles((state) => state.watched);
    final AsyncValue<List<Person>> people = switch (library) {
      AsyncValue(:final value?) => AsyncData(value.followedPeople),
      AsyncValue(:final error?) => AsyncError<List<Person>>(error, StackTrace.empty),
      _ => const AsyncLoading<List<Person>>(),
    };
    // « Mes avis ».
    final reviews = ref.watch(reviewsProvider);
    final layout = Layout.of(context);
    final year = DateTime.now().year;

    return ProfileView(
      onRefresh: () async {
        if (username.isNotEmpty) {
          ref.invalidate(socialProfileProvider(username));
          ref.invalidate(activityProvider(username));
          ref.invalidate(myListsProvider);
        }
        ref.invalidate(reviewsProvider);
        await ref.read(libraryProvider.notifier).refresh();
      },
      // « Partager le profil » (not on TV), then « Paramètres » on a phone (the tab bar has 6 tabs at
      // most). No button in the header: the shown tab takes the focus on arrival (TV).
      focusTabs: true,
      actions: [
        if (social?.shareUrl case final url? when canShareLinks)
          VxIconAction(
            icon: Icons.share_outlined,
            label: 'Partager le profil',
            dense: true,
            onPressed: () => shareLink(
              ref,
              context,
              url: url,
              message: 'Retrouve-moi sur Vixeo : ${profile.name} (@$username)',
              subject: 'Vixeo',
            ),
          ),
        if (layout.isPhone)
          VxIconAction(
            icon: Icons.settings_outlined,
            label: 'Paramètres',
            dense: true,
            onPressed: () => context.push('/parametres'),
          ),
      ],
      header: ProfileHeader(
        name: profile.name,
        avatarId: profile.avatar,
        username: username,
        isPrivate: profile.isPrivate,
        links: profile.socialLinks.isNotEmpty ? profile.socialLinks : social?.socialLinks ?? const [],
        bio: profile.bio ?? social?.bio,
        followers: social?.followersCount,
        following: social?.followingCount,
        onFollowers: () => context.push('/profil/social/abonnes'),
        onFollowing: () => context.push('/profil/social/abonnements'),
      ),
      counters: ProfileCounters(
        reviews: reviews.value?.length ?? social?.reviewsCount,
        watched: library.value?.watched.length ?? social?.watchedCount,
        titles: library.value?.toWatch.length ?? social?.listCount,
      ),
      tabs: [
        (
          label: 'Activité',
          sections: [
            if (username.isEmpty)
              const EmptyState(
                icon: Icons.alternate_email_rounded,
                title: 'Choisissez un pseudo',
                message:
                    'Dans « Qui regarde ? » → « Gérer les profils » : votre activité, vos listes et votre page '
                    'apparaîtront ici.',
              )
            else
              ProfileActivitySection(username: username, mine: true),
          ],
        ),
        (
          label: 'Listes',
          sections: [
            if (username.isEmpty)
              const ProfileColumn(child: WatchlistCard())
            else
              ProfileListsSection(username: username, mine: true),
          ],
        ),
        (
          label: 'Avis',
          sections: [
            ProfileReviewsSection(
              title: 'Mes avis',
              reviews: reviews,
              mine: true,
              emptyMessage: 'Notez un film, une série ou un épisode depuis sa fiche : votre avis apparaîtra ici.',
              onSeeAll: () => context.push('/avis'),
            ),
          ],
        ),
        (
          label: 'Aimés',
          sections: [
            ProfileTitlesSection(
              title: 'Mes J’aime',
              titles: liked,
              grid: true,
              emptyIcon: Icons.favorite_border_rounded,
              emptyTitle: 'Aucun J’aime',
              emptyMessage:
                  'Aimez des films et des séries avec le cœur de leur fiche, suivez des acteurs et des réalisateurs '
                  'depuis leur page : ils apparaîtront ici.',
              onSeeAll: () => context.push('/profil/social/aimes'),
            ),
            ProfilePeopleSection(
              title: 'Personnes suivies',
              people: people,
              onSeeAll: () => context.push('/profil/social/personnes'),
            ),
          ],
        ),
        (
          label: 'Vus',
          sections: [
            if (username.isNotEmpty && (library.value?.watched.isNotEmpty ?? false))
              ProfileColumn(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VxButton(
                    label: 'Mon année $year',
                    icon: Icons.insights_rounded,
                    kind: VxButtonKind.secondary,
                    dense: true,
                    onPressed: () => context.push(profileSectionLocation(null, 'bilan')),
                  ),
                ),
              ),
            ProfileTitlesSection(
              title: 'Mes titres vus',
              titles: watched,
              grid: true,
              emptyIcon: Icons.visibility_outlined,
              emptyTitle: 'Aucun titre vu',
              emptyMessage: 'Les films et les séries que vous marquez comme vus, ou que vous notez, apparaîtront ici.',
              onSeeAll: () => context.push('/profil/social/vus'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A member's page (`/membre/:username`): the same page as mine (`ProfileView`), with the same
/// tabs (« Activité », « Listes », « Avis », « Aimés », « Vus »), « Suivre » and, at the top right,
/// « Partager le profil » and « … ». My own page opened from a list has no button in its header.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  /// Where a member's titles, reviews or accounts open: `a-voir`, `aimes`, `vus`, `personnes`,
  /// `avis`, `abonnes`, `abonnements`.
  String _section(String section) => '/membre/${Uri.encodeComponent(username)}/$section';

  /// Opens the conversation with the member (a request when there was none).
  Future<void> _write(BuildContext context, WidgetRef ref, String username) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await startConversation(ref, username);
      if (context.mounted) await context.push(conversationLocation(id));
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } catch (_) {
      showVxSnackOn(messenger, 'Impossible d’écrire à ce membre.', icon: Icons.error_outline_rounded);
    }
  }

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

    // A private account the active profile doesn't follow: only its header (like Twitter).
    final canView = social.canView || social.isSelf;

    return Scaffold(
      body: ProfileView(
        back: true,
        onRefresh: () async {
          ref.invalidate(memberListsProvider(username));
          ref.invalidate(activityProvider(username));
          ref.invalidate(socialTitlesProvider(username));
          ref.invalidate(socialWatchedProvider(username));
          ref.invalidate(socialLikedProvider(username));
          ref.invalidate(socialPeopleProvider(username));
          ref.invalidate(socialReviewsProvider(username));
          ref.invalidate(socialProfileProvider(username));
          await ref.read(socialProfileProvider(username).future);
        },
        // « Partager le profil » (not on TV), then « … »: mute, block, report.
        focusTabs: social.isSelf,
        actions: [
          if (social.shareUrl case final url? when canShareLinks)
            VxIconAction(
              icon: Icons.share_outlined,
              label: 'Partager le profil',
              dense: true,
              onPressed: () => shareLink(
                ref,
                context,
                url: url,
                message: 'Le profil de ${social.name} (@${social.username}) sur Vixeo',
                subject: 'Vixeo',
              ),
            ),
          if (!social.isSelf && socialAvailable(ref.watch(sessionProvider)))
            VxIconAction(
              icon: Icons.more_horiz_rounded,
              label: 'Options du profil de @${social.username}',
              dense: true,
              onPressed: () => showMemberMenu(context, ref, social),
            ),
        ],
        header: ProfileHeader(
          name: social.name,
          avatarId: social.avatar,
          username: social.username,
          isPrivate: social.isPrivate,
          compatibility: social.isSelf ? null : social.compatibility,
          links: social.socialLinks,
          bio: social.bio,
          followers: social.followersCount,
          following: social.followingCount,
          onFollowers: canView ? () => context.push(_section('abonnes')) : null,
          onFollowing: canView ? () => context.push(_section('abonnements')) : null,
          action: social.isSelf ? null : _FollowButton(profile: social),
          // Write to the member (a request first, accepted or declined on its side).
          onMessage: !social.isSelf && socialAvailable(ref.watch(sessionProvider))
              ? () => _write(context, ref, social.username)
              : null,
        ),
        counters: ProfileCounters(
          reviews: social.reviewsCount,
          watched: social.watchedCount,
          titles: social.listCount,
        ),
        tabs: social.isBlocked
            ? [
                (
                  label: 'Profil',
                  sections: [
                    EmptyState(
                      icon: Icons.block_rounded,
                      title: 'Compte bloqué',
                      message:
                          'Vous avez bloqué @${social.username} : vous ne voyez plus ses publications et il ne voit plus '
                          'les vôtres. « … » en haut de la page pour le débloquer.',
                    ),
                  ],
                ),
              ]
            : canView
            ? _tabs(context, ref)
            : [
                (label: 'Profil', sections: [_PrivateAccount(profile: social)]),
              ],
      ),
    );
  }

  /// Their activity, lists, reviews, likes (and followed people) and titles watched.
  List<ProfileTab> _tabs(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(socialLikedProvider(username));
    final watched = ref.watch(socialWatchedProvider(username));
    final people = ref.watch(socialPeopleProvider(username));
    final reviews = ref.watch(socialReviewsProvider(username));
    AsyncValue<List<MediaItem>> titles(AsyncValue<List<MediaItem>> value) => switch (value.value) {
      final list? => withCatalogDetails(ref, list.take(profileGridShown).toList()),
      null when value.hasError => AsyncError<List<MediaItem>>(value.error!, StackTrace.empty),
      null => const AsyncLoading<List<MediaItem>>(),
    };
    return [
      (label: 'Activité', sections: [ProfileActivitySection(username: username)]),
      (label: 'Listes', sections: [ProfileListsSection(username: username)]),
      (
        label: 'Avis',
        sections: [
          ProfileReviewsSection(
            title: 'Ses avis',
            reviews: reviews,
            mine: false,
            emptyMessage: 'Ses notes et ses commentaires apparaîtront ici.',
            onSeeAll: () => context.push(_section('avis')),
          ),
        ],
      ),
      (
        label: 'Aimés',
        sections: [
          ProfileTitlesSection(
            title: 'Ses J’aime',
            titles: titles(liked),
            grid: true,
            emptyIcon: Icons.favorite_border_rounded,
            emptyTitle: 'Aucun J’aime',
            emptyMessage: 'Les films et les séries qu’il aime apparaîtront ici.',
            onSeeAll: () => context.push(_section('aimes')),
          ),
          ProfilePeopleSection(
            title: 'Personnes suivies',
            people: people,
            onSeeAll: () => context.push(_section('personnes')),
          ),
        ],
      ),
      (
        label: 'Vus',
        sections: [
          if (watched.value?.isNotEmpty ?? false)
            ProfileColumn(
              child: Align(
                alignment: Alignment.centerLeft,
                child: VxButton(
                  label: 'Son année ${DateTime.now().year}',
                  icon: Icons.insights_rounded,
                  kind: VxButtonKind.secondary,
                  dense: true,
                  onPressed: () => context.push(profileSectionLocation(username, 'bilan')),
                ),
              ),
            ),
          ProfileTitlesSection(
            title: 'Ses titres vus',
            titles: titles(watched),
            grid: true,
            emptyIcon: Icons.visibility_outlined,
            emptyTitle: 'Aucun titre vu',
            emptyMessage: 'Les films et les séries qu’il a vus apparaîtront ici.',
            onSeeAll: () => context.push(_section('vus')),
          ),
        ],
      ),
    ];
  }
}

/// In place of the sections of a private account the active profile doesn't follow (yet).
class _PrivateAccount extends StatelessWidget {
  const _PrivateAccount({required this.profile});

  final SocialProfile profile;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final requested = profile.followStatus == FollowStatus.requested;
    return ProfileColumn(
      child: VxCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: layout.size(28, tv: 44), color: VxColors.textSoft),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ce compte est privé', style: VxText.title(layout.size(17, tv: 28))),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Text(
                    requested
                        ? 'Votre demande d’abonnement est envoyée : son activité, ses listes, ses avis et ses '
                              'J’aime s’afficheront quand @${profile.username} l’aura acceptée.'
                        : 'Suivez @${profile.username} pour voir son activité, ses listes, ses avis, ses J’aime et '
                              'les titres qu’il a vus.',
                    style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Suivre », « Demande envoyée » (a private account hasn't accepted yet: a press withdraws the
/// request) or « Ne plus suivre » (signed in); « Se connecter pour suivre » (guest).
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.profile});

  final SocialProfile profile;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _busy = false;

  /// Unfollowing a private account hides its lists again: asked first (like Twitter).
  Future<bool> _confirmUnfollow() async {
    final username = widget.profile.username;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ne plus suivre @$username ?'),
        content: Text(
          'Ce compte est privé : pour revoir son activité, ses listes et ses avis, il faudra de nouveau demander à '
          'le suivre.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(label: 'Ne plus suivre', autofocus: true, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _toggle() async {
    final profile = widget.profile;
    final status = profile.followStatus;
    if (status == FollowStatus.following && profile.isPrivate && !await _confirmUnfollow()) return;
    if (!mounted) return;
    final repository = ref.read(socialRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final String message;
      if (status == FollowStatus.none) {
        final now = await repository.follow(profile.username);
        message = now == FollowStatus.requested
            ? 'Demande d’abonnement envoyée à @${profile.username}'
            : 'Vous suivez @${profile.username}';
      } else {
        await repository.unfollow(profile.username);
        message = status == FollowStatus.requested
            ? 'Demande d’abonnement annulée'
            : 'Vous ne suivez plus @${profile.username}';
      }
      if (!mounted) return;
      // Its counters, and its lists (shown or hidden for a private account).
      ref
        ..invalidate(socialTitlesProvider(profile.username))
        ..invalidate(socialLikedProvider(profile.username))
        ..invalidate(socialPeopleProvider(profile.username))
        ..invalidate(socialReviewsProvider(profile.username));
      ref.invalidate(socialProfileProvider(profile.username));
      showVxSnackOn(messenger, message);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } catch (_) {
      showVxSnackOn(messenger, 'Impossible de modifier l’abonnement.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.isSignedIn));
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
    final (label, icon, kind) = switch (widget.profile.followStatus) {
      FollowStatus.following => ('Ne plus suivre', Icons.person_remove_outlined, VxButtonKind.secondary),
      FollowStatus.requested => ('Demande envoyée', Icons.schedule_rounded, VxButtonKind.secondary),
      FollowStatus.none => ('Suivre', Icons.person_add_alt_1_rounded, VxButtonKind.primary),
    };
    return VxButton(label: label, icon: icon, kind: kind, dense: true, autofocus: true, loading: _busy, onPressed: _toggle);
  }
}

/// The whole « À voir », J'aime, titles watched, followed people, reviews, followers or followed
/// profiles of a member (`/membre/:username/a-voir`…) or of the active profile
/// (`/profil/social/aimes`…; mine « À voir » is `/listes/a-voir`, my reviews `/avis`). The titles
/// and the reviews are the pages of « À voir » and « Mes avis » (`MyListScreen`, `ReviewsScreen`:
/// search, filters, order); followed people: their round photos in a grid; followers and followed
/// profiles: back button, title and the members (`AccountTile`). Another section: « Page
/// introuvable » (no former address is kept).
class SocialCollectionScreen extends ConsumerWidget {
  const SocialCollectionScreen({super.key, required this.section, this.username});

  /// `a-voir` (a member's), `aimes`, `vus`, `personnes`, `avis` (a member's), `abonnes`,
  /// `abonnements`.
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
      'avis' when !mine => _Kind.reviews,
      'a-voir' when !mine => _Kind.toWatch,
      'aimes' => _Kind.liked,
      'vus' => _Kind.watched,
      'personnes' => _Kind.people,
      'abonnes' => _Kind.followers,
      'abonnements' => _Kind.following,
      _ => null,
    };
    switch (kind) {
      case null:
        return const Scaffold(
          body: EmptyState(icon: Icons.explore_off_outlined, title: 'Page introuvable'),
        );
      case _Kind.toWatch:
        return MyListScreen(username: handle);
      case _Kind.liked:
        return MyListScreen(username: mine ? null : handle, collection: TitleCollection.liked);
      case _Kind.watched:
        return MyListScreen(username: mine ? null : handle, collection: TitleCollection.watched);
      case _Kind.reviews:
        return ReviewsScreen(username: handle);
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

enum _Kind { toWatch, liked, watched, people, reviews, followers, following }

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

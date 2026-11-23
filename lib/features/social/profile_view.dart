import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../profiles/avatars.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'social_links.dart';
import 'social_repository.dart';

// The page of a profile, the same for mine (« Profil » tab, `ProfileScreen`) and for another
// member's (`/membre/:username`, `PublicProfileScreen`). Each screen gives its data (its own
// providers) and its button; the layout, the sizes and the sections are here only.
//
// Flutter: these are widgets with parameters, like Vue components with props. A screen builds
// `ProfileView(header: ProfileHeader(...), counters: ProfileCounters(...), sections: [...])`.

/// Titles shown in a row of a profile page (the most recently added).
const profileTitlesShown = 20;

/// Reviews shown in the « Avis » tab of a profile page (the most recent).
const profileReviewsShown = 10;

/// Titles shown in a grid of a tab (« Aimés », « Vus »), before « Voir tout ».
const profileGridShown = 18;

/// A tab of a profile page (« Activité », « Listes », « Avis », « Aimés », « Vus »): its sections.
typedef ProfileTab = ({String label, List<Widget> sections});

/// A profile's page: header, counters, then its sections (a list, reviews…), in a page that
/// scrolls and refreshes when pulled down. With several [tabs], a row of tabs under the counters
/// chooses the sections shown. [back]: a round back button above the header (a member's page,
/// opened over another page); [actions]: round buttons at the top right (« Partager le profil »,
/// then « Paramètres » of my page on a phone or « … » of a member). [focusTabs]: the shown tab
/// takes the focus on arrival (TV), when the header has no button to take it (my page).
class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.header,
    required this.counters,
    required this.tabs,
    required this.onRefresh,
    this.back = false,
    this.actions = const [],
    this.focusTabs = false,
  });

  final Widget header;
  final Widget counters;
  final List<ProfileTab> tabs;
  final Future<void> Function() onRefresh;
  final bool back;
  final List<Widget> actions;
  final bool focusTabs;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final tabs = widget.tabs;
    final tab = _tab < tabs.length ? _tab : 0;
    final top = widget.back || widget.actions.isNotEmpty;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: top ? layout.space(VxSpace.xs) : layout.space(VxSpace.m),
            bottom: pageBottomPadding(context),
          ),
          children: [
            if (top) ...[
              ProfileColumn(
                child: Row(
                  children: [
                    if (widget.back) const VxBackButton(),
                    const Spacer(),
                    for (final (i, action) in widget.actions.indexed) ...[
                      if (i > 0) SizedBox(width: layout.space(VxSpace.xs)),
                      action,
                    ],
                  ],
                ),
              ),
              SizedBox(height: layout.space(VxSpace.m)),
            ],
            ProfileColumn(child: widget.header),
            SizedBox(height: layout.sectionGap),
            ProfileColumn(child: widget.counters),
            if (tabs.length > 1) ...[
              SizedBox(height: layout.sectionGap),
              ProfileColumn(
                child: VxTabs(
                  labels: [for (final t in tabs) t.label],
                  selected: tab,
                  autofocus: widget.focusTabs,
                  onSelected: (i) => setState(() => _tab = i),
                ),
              ),
            ],
            for (final section in tabs.isEmpty ? const <Widget>[] : tabs[tab].sections) ...[
              SizedBox(height: layout.sectionGap),
              section,
            ],
          ],
        ),
      ),
    );
  }
}

/// The reading column of a profile page: page margins, 900 wide at most (TV 1500), on the left.
class ProfileColumn extends StatelessWidget {
  const ProfileColumn({super.key, required this.child});

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

/// Avatar, name, @username, followers and following, bio, then the page's button ([action]:
/// « Suivre » of a member, which takes the focus on arrival; none on my page: its biography and
/// networks are changed in « Paramètres »).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    this.avatarId,
    this.photoUrl,
    this.username,
    this.bio,
    this.followers,
    this.following,
    this.onFollowers,
    this.onFollowing,
    this.action,
    this.onMessage,
    this.isPrivate = false,
    this.links = const [],
    this.compatibility,
  });

  final String name;

  /// Avatar of the catalog (`GET /avatars`); without one, the initial of [name].
  final String? avatarId;

  /// Its own photo, shown instead of the avatar.
  final String? photoUrl;
  final String? username;
  final String? bio;

  /// Null while they load: the line is not shown yet.
  final int? followers;
  final int? following;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;
  final Widget? action;

  /// « Envoyer un message » (a round button beside [action]); none when null (my profile, a guest,
  /// a child's profile).
  final VoidCallback? onMessage;

  /// A private account: a lock after the name.
  final bool isPrivate;

  /// Its accounts on social networks, under the bio (a press opens the page).
  final List<SocialLink> links;

  /// Tastes in common with the active profile, 0 to 100 (a member's page): « 82 % de goûts en
  /// commun ».
  final int? compatibility;

  /// "L" for "Léa", as `Profile.initial`.
  static String initialOf(String name) => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(88, tv: 160);
    final handle = username?.trim() ?? '';
    final text = bio?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AvatarTile(
              avatarId: avatarId,
              photoUrl: photoUrl,
              initial: initialOf(name),
              size: avatar,
              radius: avatar / 2,
            ),
            SizedBox(width: layout.space(VxSpace.m)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.title(layout.size(24, tv: 48)),
                        ),
                      ),
                      if (isPrivate) ...[
                        SizedBox(width: layout.space(VxSpace.xs)),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: layout.size(20, tv: 36),
                          color: VxColors.textSecondary,
                          semanticLabel: 'Compte privé',
                        ),
                      ],
                    ],
                  ),
                  if (handle.isNotEmpty) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    Text(
                      '@$handle',
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
                        _FollowLink(count: followers!, one: 'abonné', many: 'abonnés', onPressed: onFollowers),
                        _FollowLink(
                          count: following!,
                          one: 'abonnement',
                          many: 'abonnements',
                          onPressed: onFollowing,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (compatibility case final score?) ...[
          SizedBox(height: layout.space(VxSpace.s)),
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: layout.size(16, tv: 26), color: VxColors.accent),
              SizedBox(width: layout.space(VxSpace.xs)),
              Text(
                '$score % de goûts en commun',
                style: VxText.body(layout.captionSize, weight: FontWeight.w700, color: VxColors.accent),
              ),
            ],
          ),
        ],
        if (text.isNotEmpty) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          Text(text, style: VxText.body(layout.bodySize, color: VxColors.textSoft)),
        ],
        if (links.isNotEmpty) ...[
          SizedBox(height: layout.space(VxSpace.s)),
          Wrap(
            spacing: layout.space(VxSpace.xs),
            runSpacing: layout.space(VxSpace.xs),
            children: [for (final link in links) SocialLinkChip(link: link)],
          ),
        ],
        if (action != null || onMessage != null) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          Row(
            children: [
              if (action != null) Flexible(child: action!),
              if (onMessage != null) ...[
                if (action != null) SizedBox(width: layout.space(VxSpace.s)),
                VxIconAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: username == null ? 'Envoyer un message' : 'Envoyer un message à @$username',
                  dense: true,
                  onPressed: onMessage,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// An account of the profile on a social network: its icon and `@lea` (or the website). A press
/// opens the page in the browser; on a TV (often without a browser), it is only shown.
class SocialLinkChip extends StatelessWidget {
  const SocialLinkChip({super.key, required this.link});

  final SocialLink link;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(link.url);
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened) showVxSnackOn(messenger, 'Impossible d’ouvrir ce lien.', icon: Icons.error_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.captionSize;
    final radius = layout.size(VxRadius.button, tv: VxRadius.buttonTv);
    return VxFocusable(
      borderRadius: radius,
      semanticLabel: '${link.network.label} : ${link.display}',
      onPressed: DeviceInfo.isTv ? null : () => _open(context),
      child: Container(
        constraints: BoxConstraints(minHeight: layout.size(36, tv: 56)),
        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s)),
        decoration: BoxDecoration(
          color: VxColors.text.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(link.network.icon, size: size * 1.3, color: VxColors.textSoft),
            SizedBox(width: layout.space(VxSpace.xxs) * 1.5),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.size(220, tv: 400)),
              child: Text(
                link.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VxText.body(size, color: VxColors.textSoft, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "12 abonnés": opens the list of followers (or of followed profiles).
class _FollowLink extends StatelessWidget {
  const _FollowLink({required this.count, required this.one, required this.many, this.onPressed});

  final int count;
  final String one;
  final String many;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.bodySize;
    // French: "0 abonné", "1 abonné", "2 abonnés".
    final word = count > 1 ? many : one;
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: '$count $word',
      onPressed: onPressed,
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

/// Reviews, watched titles and titles « À voir », side by side in a card. A null count (not
/// loaded yet) is a dash.
class ProfileCounters extends StatelessWidget {
  const ProfileCounters({super.key, this.reviews, this.watched, this.titles, this.titlesLabel = 'À voir'});

  final int? reviews;
  final int? watched;
  final int? titles;
  final String titlesLabel;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final divider = Container(width: 1, height: layout.size(36, tv: 64), color: VxColors.line);
    return VxCard(
      padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.m), horizontal: layout.space(VxSpace.xs)),
      child: Row(
        children: [
          Expanded(child: _Counter(value: reviews, label: 'Avis')),
          divider,
          Expanded(child: _Counter(value: watched, label: 'Vus')),
          divider,
          Expanded(child: _Counter(value: titles, label: titlesLabel)),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.label});

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
          Text(value?.toString() ?? '–', maxLines: 1, style: VxText.title(layout.size(22, tv: 44))),
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

/// [titles] completed by the catalog (rating, logo, summary) in one request: never one per card.
/// Loading until the catalog answers the first time, so that the cards come with their logo.
AsyncValue<List<MediaItem>> withCatalogDetails(WidgetRef ref, List<MediaItem> titles) {
  if (titles.isEmpty) return const AsyncData(<MediaItem>[]);
  final batch = ref.watch(titlesByIdProvider(titlesKey(titles.map((t) => (type: t.type, id: t.id)))));
  if (!batch.hasValue && batch.isLoading) return const AsyncLoading<List<MediaItem>>();
  final known = batch.value ?? const <TitleRef, MediaItem>{};
  return AsyncData([for (final title in titles) title.withDetails(known[(type: title.type, id: title.id)])]);
}

/// Titles of a profile (« Mes J'aime », « Vus »…): a row of posters, as on the home page, or a
/// [grid] (the first [profileGridShown], a tab of their own); the round arrow ([onSeeAll]) opens
/// them all. None: the [EmptyState] of the app ([emptyIcon], [emptyTitle], [emptyMessage]).
class ProfileTitlesSection extends ConsumerWidget {
  const ProfileTitlesSection({
    super.key,
    required this.title,
    required this.titles,
    required this.emptyMessage,
    this.emptyTitle = 'Rien pour l’instant',
    this.emptyIcon = Icons.movie_outlined,
    this.onSeeAll,
    this.grid = false,
  });

  final String title;
  final AsyncValue<List<MediaItem>> titles;
  final String emptyMessage;
  final String emptyTitle;
  final IconData emptyIcon;
  final VoidCallback? onSeeAll;
  final bool grid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final format = posterFormatOf(ref);
    final width = rowCardWidth(layout, format);
    final rowHeight =
        PosterCard.heightFor(width, format) +
        PosterCard.captionHeightOf(context) +
        (layout.isLarge ? layout.tv(16) * 2 : 0);

    final items = titles.value;
    if (items == null) {
      return titles.hasError
          ? ProfileSectionMessage(title: title, message: 'Impossible de charger cette liste.')
          : ProfileSectionLoading(title: title, height: rowHeight);
    }
    if (items.isEmpty) return EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage);
    if (!grid) return PosterRow(title: title, items: items, onSeeAll: onSeeAll);
    final shown = items.take(profileGridShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, onSeeAll: onSeeAll),
        FocusTraversalGroup(
          policy: vxTraversalPolicy,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Room for the focus zoom on TV.
            padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(16) : 0),
            gridDelegate: posterGridDelegate(layout, format, captionHeight: PosterCard.captionHeightOf(context)),
            itemCount: shown.length,
            itemBuilder: (context, i) => LayoutBuilder(
              builder: (context, c) => PosterCard(item: shown[i], width: c.maxWidth, format: format),
            ),
          ),
        ),
      ],
    );
  }
}

/// The people a profile follows (« Personnes suivies »): a row of round photos, as the cast of a
/// title page; the round arrow ([onSeeAll]) opens them all. None: nothing (the tab's other section
/// says how to follow people).
class ProfilePeopleSection extends StatelessWidget {
  const ProfilePeopleSection({super.key, required this.title, required this.people, this.onSeeAll});

  final String title;
  final AsyncValue<List<Person>> people;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final height = PersonCard.heightOf(layout, withRole: false) + (layout.isLarge ? layout.tv(32) : 0);
    final all = people.value;
    if (all == null) {
      return people.hasError
          ? ProfileSectionMessage(title: title, message: 'Impossible de charger cette liste.')
          : ProfileSectionLoading(title: title, height: height);
    }
    if (all.isEmpty) return const SizedBox.shrink();

    final shown = all.take(profileTitlesShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, onSeeAll: onSeeAll),
        FocusTraversalGroup(
          policy: vxTraversalPolicy,
          child: SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              // Room for the focus zoom on TV.
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(16) : 0),
              itemCount: shown.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (_, i) => PersonCard(person: shown[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reviews of a profile (« Mes avis », « Ses avis »): the latest [profileReviewsShown], the same rows as the
/// « Mes avis » page; the round arrow ([onSeeAll]) opens them all. [mine]: a review opens
/// « Mon avis » to change it; otherwise, the title. None: the [EmptyState] of the app.
class ProfileReviewsSection extends StatelessWidget {
  const ProfileReviewsSection({
    super.key,
    required this.title,
    required this.reviews,
    required this.emptyMessage,
    required this.mine,
    this.emptyTitle = 'Aucun avis',
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<List<RatedItem>> reviews;
  final String emptyMessage;
  final String emptyTitle;
  final bool mine;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final all = reviews.value;
    if (all == null) {
      return reviews.hasError
          ? ProfileSectionMessage(title: title, message: 'Impossible de charger les avis.')
          : ProfileSectionLoading(title: title, height: layout.size(96, tv: 160));
    }
    if (all.isEmpty) return EmptyState(icon: Icons.star_outline_rounded, title: emptyTitle, message: emptyMessage);

    final latest = all.take(profileReviewsShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, onSeeAll: onSeeAll),
        ProfileColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, item) in latest.indexed) ...[
                if (i > 0) SizedBox(height: layout.listGap),
                ReviewRow(item: item, mine: mine),
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
class ProfileSectionMessage extends StatelessWidget {
  const ProfileSectionMessage({super.key, required this.title, required this.message, this.action});

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
        ProfileColumn(
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
class ProfileSectionLoading extends StatelessWidget {
  const ProfileSectionLoading({super.key, required this.title, required this.height});

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

/// A member in a list (account search, followers): avatar, name and @username. Opens their page.
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.profile, this.autofocus = false});

  final SocialProfile profile;
  final bool autofocus;

  /// Where a member's page opens.
  static String location(String username) => '/membre/${Uri.encodeComponent(username)}';

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(48, tv: 80);
    final name = profile.name.trim().isEmpty ? '@${profile.username}' : profile.name;
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: '$name, @${profile.username}',
      autofocus: autofocus,
      onPressed: () => context.push(location(profile.username)),
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            AvatarTile(
              avatarId: profile.avatar,
              photoUrl: profile.photoUrl,
              initial: ProfileHeader.initialOf(profile.name),
              size: avatar,
              radius: avatar / 2,
            ),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
                        ),
                      ),
                      if (profile.isPrivate) ...[
                        SizedBox(width: layout.space(VxSpace.xxs)),
                        Icon(Icons.lock_outline_rounded, size: layout.size(15, tv: 24), color: VxColors.textSecondary),
                      ],
                    ],
                  ),
                  Text(
                    '@${profile.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(width: layout.space(VxSpace.xs)),
            Icon(Icons.chevron_right_rounded, size: layout.size(22, tv: 34), color: VxColors.textMuted),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../profiles/avatars.dart';
import '../profiles/covers.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'social_links.dart';
import 'social_repository.dart';

// The page of a profile, the same for mine (« Profil » tab, `ProfileScreen`) and for another
// member's (`/membre/:username`, `PublicProfileScreen`). Each screen gives its data (its own
// providers) and its button; the layout, the sizes and the sections are here only.
//
// Flutter: these are widgets with parameters, like Vue components with props. A screen builds
// `ProfileView(header: ProfileHeader(...), stats: ProfileStats(...), tabs: [...])`.

/// Titles shown in a row of a profile page (the most recently added).
const profileTitlesShown = 20;

/// Reviews shown in the « Avis » tab of a profile page (the most recent).
const profileReviewsShown = 10;

/// Titles shown in a grid of a tab (« Aimés », « Vus »), before « Voir tout ».
const profileGridShown = 18;

/// A tab of a profile page (« Activité », « Listes », « Avis », « Aimés », « Vus »): its sections.
typedef ProfileTab = ({String label, List<Widget> sections});

/// A profile's page (like Bingers, developer's request, 25/11/2026): its cover (the banner at the
/// top, [cover]: `ProfileCover`), its header (its avatar on the left, over the bottom of the cover),
/// its figures ([stats]: `ProfileStats`, cards side by side), then its sections (a list, reviews…),
/// in a page that scrolls and refreshes when pulled down. With several [tabs], a row of tabs under
/// the figures chooses the sections shown. [back]: a round back button on the cover (a member's
/// page, opened over another page); [actions]: round buttons at the top right of the cover
/// (« Partager le profil », « Notifications » and « ⋮ » of my page, « ⋮ » of a member).
/// [focusTabs]: the shown tab takes the focus on arrival (TV), when the header has no button to
/// take it (my page).
class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.cover,
    required this.header,
    required this.stats,
    required this.tabs,
    required this.onRefresh,
    this.back = false,
    this.actions = const [],
    this.focusTabs = false,
  });

  final Widget cover;
  final Widget header;
  final Widget stats;
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
    final buttons = widget.back || widget.actions.isNotEmpty;
    final list = RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: layout.isPhone ? 0 : layout.space(VxSpace.xs), bottom: pageBottomPadding(context)),
          children: [
            _ProfileBanner(cover: widget.cover, shaded: buttons),
            ProfileColumn(child: widget.header),
            SizedBox(height: layout.sectionGap),
            widget.stats,
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
      );
    // The back button and the actions stay at the top while the page scrolls under them, at the
    // corners of the cover (in the reading column on a large screen).
    final bar = VxFloatingBar(
      back: widget.back,
      actions: widget.actions,
      safeArea: false,
      padding: layout.isPhone
          ? EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.xs), layout.gutter, 0)
          : EdgeInsets.fromLTRB(layout.space(VxSpace.s), layout.space(VxSpace.xs) * 2, layout.space(VxSpace.s), 0),
    );
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          list,
          if (buttons)
            Positioned(top: 0, left: 0, right: 0, child: layout.isPhone ? bar : ProfileColumn(child: bar)),
        ],
      ),
    );
  }
}

/// The cover at the top of a profile page, twice the former 3:1 height: across the whole screen on
/// a phone, in the reading column with rounded corners elsewhere; [shaded]: a light shade at its top, under the page's
/// buttons (`VxFloatingBar`), that keeps them readable on a bright cover.
class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.cover, required this.shaded});

  final Widget cover;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    Widget banner(double width, double radius) {
      final height = math.min(width / coverAspectRatio * 2, layout.size(400, tv: 680));
      return SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(radius), child: cover),
            if (shaded)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (layout.isPhone) {
      return LayoutBuilder(builder: (context, constraints) => banner(constraints.maxWidth, 0));
    }
    final radius = layout.size(VxRadius.card, tv: VxRadius.cardTv);
    return ProfileColumn(child: LayoutBuilder(builder: (context, constraints) => banner(constraints.maxWidth, radius)));
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

/// The top of a profile page, under its cover (like Bingers, developer's request, 25/11/2026): the
/// avatar on the left, half over the cover, and on its right the page's buttons (a member's
/// « Envoyer un message » ([onMessage]) and « Suivre » ([action], which takes the focus on arrival);
/// none on my page); then, aligned on the left, the name, @username, tastes in common, following,
/// followers and followed people (actors, directors…: a press opens each list), bio and networks.
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
    this.people,
    this.onFollowers,
    this.onFollowing,
    this.onPeople,
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

  /// Followed people (actors, directors…); null: not shown.
  final int? people;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;
  final VoidCallback? onPeople;
  final Widget? action;

  /// « Envoyer un message » (a round button before [action]); none when null (my profile,
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
    final avatar = layout.size(96, tv: 170);
    final ring = layout.size(4, tv: 6);
    final handle = username?.trim() ?? '';
    final text = bio?.trim() ?? '';
    final buttons = action != null || onMessage != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The avatar half over the bottom of the cover, in a ring of the page's color; the buttons
        // on its right, under the cover.
        SizedBox(
          height: avatar / 2 + ring,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -ring,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.all(ring),
                  decoration: const BoxDecoration(color: VxColors.background, shape: BoxShape.circle),
                  child: AvatarTile(
                    avatarId: avatarId,
                    photoUrl: photoUrl,
                    initial: initialOf(name),
                    size: avatar,
                    radius: avatar / 2,
                  ),
                ),
              ),
              if (buttons)
                Positioned(
                  left: avatar + layout.space(VxSpace.s),
                  right: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onMessage != null)
                        VxIconAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: username == null ? 'Envoyer un message' : 'Envoyer un message à @$username',
                          dense: true,
                          onPressed: onMessage,
                        ),
                      if (action != null) ...[
                        if (onMessage != null) SizedBox(width: layout.space(VxSpace.xs)),
                        Flexible(child: action!),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: layout.space(VxSpace.s)),
        Row(
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 2,
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
        if (compatibility case final score?) ...[
          SizedBox(height: layout.space(VxSpace.xs)),
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
        if (followers != null && following != null) ...[
          SizedBox(height: layout.space(VxSpace.xxs)),
          Wrap(
            spacing: layout.space(VxSpace.m),
            children: [
              _FollowLink(count: following!, one: 'Abonnement', many: 'Abonnements', onPressed: onFollowing),
              _FollowLink(count: followers!, one: 'Abonné', many: 'Abonnés', onPressed: onFollowers),
              if (people case final count?)
                _FollowLink(count: count, one: 'Personne suivie', many: 'Personnes suivies', onPressed: onPeople),
            ],
          ),
        ],
        if (text.isNotEmpty) ...[
          SizedBox(height: layout.space(VxSpace.xs)),
          ConstrainedBox(
            // A short line, easy to read.
            constraints: BoxConstraints(maxWidth: layout.size(560, tv: 1000)),
            child: Text(text, style: VxText.body(layout.bodySize, color: VxColors.textSoft)),
          ),
        ],
        if (links.isNotEmpty) ...[
          SizedBox(height: layout.space(VxSpace.s)),
          Wrap(
            spacing: layout.space(VxSpace.xs),
            runSpacing: layout.space(VxSpace.xs),
            children: [for (final link in links) SocialLinkChip(link: link)],
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

/// "12 Abonnés": opens the list of followers (or of followed profiles, or of followed people).
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
    // French: "0 Abonné", "1 Abonné", "2 Abonnés"; "1 Personne suivie", "2 Personnes suivies".
    final word = count > 1 ? many : one;
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: '$count ${word.toLowerCase()}',
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

/// A figure of a profile page: its label, its value as shown (null: loading, a dash) and as read by
/// screen readers ([spoken]; the value when null).
typedef ProfileStat = ({String label, String? value, String? spoken});

ProfileStat profileStat(String label, int? count) => (label: label, value: count?.toString(), spoken: null);

/// The time watched as the profile page shows it: « 3 mois 21 j 9 h », « 2 j 4 h », « 5 h 12 min »,
/// « 40 min » (a month is 30 days), and as screen readers say it.
({String shown, String spoken}) watchTimeLabel(int minutes) {
  if (minutes <= 0) return (shown: '0 h', spoken: 'aucun');
  final hours = minutes ~/ 60;
  final days = hours ~/ 24;
  final months = days ~/ 30;
  String plural(int n, String one, String many) => '$n ${n > 1 ? many : one}';
  final List<(int, String, String, String)> parts;
  if (days == 0) {
    parts = [(hours, 'h', 'heure', 'heures'), (minutes % 60, 'min', 'minute', 'minutes')];
  } else if (months == 0) {
    parts = [(days, 'j', 'jour', 'jours'), (hours % 24, 'h', 'heure', 'heures')];
  } else {
    parts = [(months, 'mois', 'mois', 'mois'), (days % 30, 'j', 'jour', 'jours'), (hours % 24, 'h', 'heure', 'heures')];
  }
  final kept = [for (final part in parts) if (part.$1 > 0) part];
  final spoken = [for (final (n, _, one, many) in kept) plural(n, one, many)];
  return (
    shown: [for (final (n, unit, _, _) in kept) '$n $unit'].join(' '),
    spoken: spoken.length > 1
        ? '${spoken.sublist(0, spoken.length - 1).join(', ')} et ${spoken.last}'
        : spoken.single,
  );
}

/// The figures of a profile page (like Bingers, developer's request, 25/11/2026): a card each, its
/// label in capitals above its value (« TEMPS DE VISIONNAGE », « 3 mois 21 j 9 h »). On a phone they
/// scroll from left to right (the next one shows at the edge); on larger screens they share the
/// width of the reading column (nothing to scroll with a remote).
class ProfileStats extends StatelessWidget {
  const ProfileStats({super.key, required this.stats});

  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final gap = layout.space(VxSpace.xs);
    if (!layout.isPhone) {
      return ProfileColumn(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, stat) in stats.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: _StatCard(stat: stat)),
              ],
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two cards and a bit of the third: there are more to see.
        final width = (constraints.maxWidth - layout.gutter - gap * 2) / 2.3;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, stat) in stats.indexed) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(width: width, child: _StatCard(stat: stat)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final ProfileStat stat;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final radius = layout.size(VxRadius.card, tv: VxRadius.cardTv) * 0.8;
    final value = stat.value;
    return Semantics(
      container: true,
      label: '${stat.label} : ${value == null ? 'chargement' : stat.spoken ?? value}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s), vertical: layout.space(VxSpace.s)),
        decoration: BoxDecoration(
          color: VxColors.surfaceHigh,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: VxColors.text.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              stat.label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(
                layout.size(11, tv: 18),
                weight: FontWeight.w700,
                color: VxColors.textSecondary,
              ).copyWith(letterSpacing: 0.6),
            ),
            SizedBox(height: layout.space(VxSpace.xs)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value ?? '–', maxLines: 1, style: VxText.title(layout.size(22, tv: 40))),
            ),
          ],
        ),
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
    final width = rowCardWidth(layout);
    final rowHeight =
        PosterCard.heightFor(width) +
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
            gridDelegate: posterGridDelegate(layout, captionHeight: PosterCard.captionHeightOf(context)),
            itemCount: shown.length,
            itemBuilder: (context, i) => LayoutBuilder(
              builder: (context, c) => PosterCard(item: shown[i], width: c.maxWidth),
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

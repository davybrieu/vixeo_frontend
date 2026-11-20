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
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../profiles/avatars.dart';
import '../tmdb/reviews_screen.dart';
import '../tmdb/tmdb.dart';
import 'social_repository.dart';

// The page of a profile, the same for mine (« Profil » tab, `ProfileScreen`) and for another
// member's (`/membre/:username`, `PublicProfileScreen`). Each screen gives its data (its own
// providers) and its button; the layout, the sizes and the sections are here only.
//
// Flutter: these are widgets with parameters, like Vue components with props. A screen builds
// `ProfileView(header: ProfileHeader(...), counters: ProfileCounters(...), sections: [...])`.

/// Titles shown in a row of a profile page (the most recently added).
const profileTitlesShown = 20;

/// Reviews shown on a profile page (the most recent).
const profileReviewsShown = 3;

/// A profile's page: header, counters, then its sections (a list, reviews…), in a page that
/// scrolls and refreshes when pulled down. [back]: a round back button above the header (a member's
/// page, opened over another page).
class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.header,
    required this.counters,
    required this.sections,
    required this.onRefresh,
    this.back = false,
  });

  final Widget header;
  final Widget counters;
  final List<Widget> sections;
  final Future<void> Function() onRefresh;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: back ? layout.space(VxSpace.xs) : layout.space(VxSpace.m),
            bottom: pageBottomPadding(context),
          ),
          children: [
            if (back) ...[
              ProfileColumn(child: Align(alignment: Alignment.centerLeft, child: const VxBackButton())),
              SizedBox(height: layout.space(VxSpace.m)),
            ],
            ProfileColumn(child: header),
            SizedBox(height: layout.sectionGap),
            ProfileColumn(child: counters),
            for (final section in sections) ...[SizedBox(height: layout.sectionGap), section],
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
/// « Modifier le profil », « Suivre »…), which takes the focus on arrival.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    this.avatarId,
    this.username,
    this.bio,
    this.emptyBio,
    this.followers,
    this.following,
    this.onFollowers,
    this.onFollowing,
    this.action,
  });

  final String name;

  /// Avatar of the catalog (`GET /avatars`); without one, the initial of [name].
  final String? avatarId;
  final String? username;
  final String? bio;

  /// Shown, dimmed, when there is no bio (mine: an invitation); none when null.
  final String? emptyBio;

  /// Null while they load: the line is not shown yet.
  final int? followers;
  final int? following;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;
  final Widget? action;

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
            AvatarTile(avatarId: avatarId, initial: initialOf(name), size: avatar, radius: avatar / 2),
            SizedBox(width: layout.space(VxSpace.m)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.title(layout.size(24, tv: 48)),
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
        if (text.isNotEmpty || emptyBio != null) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          Text(
            text.isEmpty ? emptyBio! : text,
            style: VxText.body(layout.bodySize, color: text.isEmpty ? VxColors.textMuted : VxColors.textSoft),
          ),
        ],
        if (action != null) ...[SizedBox(height: layout.space(VxSpace.m)), action!],
      ],
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

/// Reviews, watched titles and titles in the list, side by side in a card. A null count (not
/// loaded yet) is a dash.
class ProfileCounters extends StatelessWidget {
  const ProfileCounters({super.key, this.reviews, this.watched, this.titles, this.titlesLabel = 'Ma liste'});

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

/// A list of a profile (« Ma liste », « Sa liste »): a row of posters, as on the home page; the
/// round arrow ([onSeeAll]) opens the whole list.
class ProfileTitlesSection extends ConsumerWidget {
  const ProfileTitlesSection({
    super.key,
    required this.title,
    required this.titles,
    required this.emptyMessage,
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<List<MediaItem>> titles;
  final String emptyMessage;
  final VoidCallback? onSeeAll;

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
    if (items.isEmpty) return ProfileSectionMessage(title: title, message: emptyMessage);
    return PosterRow(title: title, items: items, onSeeAll: onSeeAll);
  }
}

/// The people a profile follows (« Personnes suivies »): a row of round photos, as the cast of a
/// title page; the round arrow ([onSeeAll]) opens them all.
class ProfilePeopleSection extends StatelessWidget {
  const ProfilePeopleSection({
    super.key,
    required this.title,
    required this.people,
    required this.emptyMessage,
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<List<Person>> people;
  final String emptyMessage;
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
    if (all.isEmpty) return ProfileSectionMessage(title: title, message: emptyMessage);

    final shown = all.take(profileTitlesShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, onSeeAll: onSeeAll),
        FocusTraversalGroup(
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

/// Reviews of a profile (« Mes avis », « Ses avis »): the latest ones, the same rows as the
/// « Mes avis » page; the round arrow ([onSeeAll]) opens them all. [mine]: a review opens
/// « Mon avis » to change it; otherwise, the title.
class ProfileReviewsSection extends StatelessWidget {
  const ProfileReviewsSection({
    super.key,
    required this.title,
    required this.reviews,
    required this.emptyMessage,
    required this.mine,
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<List<RatedItem>> reviews;
  final String emptyMessage;
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
    if (all.isEmpty) return ProfileSectionMessage(title: title, message: emptyMessage);

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
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
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

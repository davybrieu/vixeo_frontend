import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../messages/conversations_screen.dart';
import '../messages/messages.dart' show unreadMessagesProvider;
import '../profiles/avatars.dart';
import '../shell/app_shell.dart' show NavigationBadge, unreadMessagesLabel;
import '../social/profile_view.dart' show AccountTile, ProfileHeader;
import '../social/social_repository.dart';
import 'network.dart';
import 'widgets.dart';

/// « Fil » (`/fil`, in the navigation of phones, tablets and computers; not on a TV, nor for a
/// guest or a child's profile; vixeo_backend/docs/social.md): what the followed members did, the
/// most recent first — reviews, lists and top 10, titles watched (grouped: « Léa et Max ont vu… »).
/// No text post: everything is about a title. Accounts to follow come after the first posts (or
/// alone, when the feed is empty). On a phone, « Messages » is the round button of the header.
///
/// Flutter: the page reads `feedProvider` (like a Pinia store with an action `loadMore`); the next
/// page is asked when the list nears its end (a listener on the scroll, like an
/// IntersectionObserver).
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  static const location = '/fil';

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 800) unawaited(ref.read(feedProvider.notifier).loadMore());
  }

  Future<void> _refresh() async {
    ref.invalidate(feedProvider);
    ref.invalidate(suggestionsProvider);
    try {
      await ref.read(feedProvider.future);
    } catch (_) {
      // The page shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final feed = ref.watch(feedProvider);
    final unread = ref.watch(unreadMessagesProvider);
    final badge = layout.size(18, tv: 28);

    final List<Widget> content = switch (feed) {
      AsyncValue(value: final page?) => [
        if (page.items.isEmpty) ...[
          const EmptyState(
            icon: Icons.dynamic_feed_outlined,
            title: 'Votre fil est vide',
            message: 'Suivez des membres : leurs avis, leurs listes et ce qu’ils regardent apparaîtront ici.',
          ),
          const _Suggestions(),
        ],
        for (final (i, item) in page.items.indexed) ...[
          if (i > 0) SizedBox(height: layout.listGap),
          _FeedEntry(item: item),
          // Accounts to follow after the third post.
          if (i == 2) ...[SizedBox(height: layout.sectionGap), const _Suggestions()],
        ],
        if (page.items.isNotEmpty && page.items.length < 3) ...[
          SizedBox(height: layout.sectionGap),
          const _Suggestions(),
        ],
        if (page.next != null)
          Padding(
            padding: EdgeInsets.only(top: layout.sectionGap),
            child: Center(
              child: VxButton(
                label: 'Afficher plus',
                kind: VxButtonKind.outline,
                dense: true,
                onPressed: () => ref.read(feedProvider.notifier).loadMore(),
              ),
            ),
          ),
      ],
      AsyncValue(:final error?) => [ErrorPanel(error: error, onRetry: () => ref.invalidate(feedProvider))],
      _ => [
        const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: 'Fil',
            actions: [
              // Tablets and computers have « Messages » in the rail.
              if (layout.isPhone)
                NavigationBadge(
                  count: unread,
                  size: badge,
                  child: VxIconAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: unread > 0 ? 'Messages, ${unreadMessagesLabel(unread)}' : 'Messages',
                    dense: true,
                    onPressed: () => context.push(ConversationsScreen.location),
                  ),
                ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pageContentPadding(context),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: layout.size(680, tv: 1100)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedEntry extends StatelessWidget {
  const _FeedEntry({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) => switch (item) {
    FeedReview(:final review, :final createdAt) => ReviewPost(review: review, at: createdAt),
    FeedList(:final list, :final createdAt) => ListPost(list: list, at: createdAt),
    final FeedWatched watched => WatchedPost(item: watched),
  };
}

/// « Comptes à suivre »: members with the same tastes, or followed by the members I follow, in
/// a row of cards with « Suivre ».
class _Suggestions extends ConsumerWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final suggestions = ref.watch(suggestionsProvider).value ?? const <Suggestion>[];
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Comptes à suivre', padding: EdgeInsets.only(bottom: layout.titleGap)),
        SizedBox(
          height: SuggestionCard.heightOf(layout),
          child: FocusTraversalGroup(
            policy: vxTraversalPolicy,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (context, i) => SuggestionCard(suggestion: suggestions[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// An account to follow: avatar, name, @pseudo, why (« 82 % de goûts en commun », « Suivi par
/// Léa »), « Suivre ».
class SuggestionCard extends ConsumerStatefulWidget {
  const SuggestionCard({super.key, required this.suggestion});

  final Suggestion suggestion;

  static double widthOf(Layout layout) => layout.size(168, tv: 280);
  static double heightOf(Layout layout) => layout.size(236, tv: 390);

  @override
  ConsumerState<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<SuggestionCard> {
  FollowStatus _status = FollowStatus.none;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final profile = widget.suggestion.profile;
    setState(() => _busy = true);
    try {
      final repository = ref.read(socialRepositoryProvider);
      if (_status == FollowStatus.none) {
        final status = await repository.follow(profile.username);
        if (mounted) setState(() => _status = status);
        if (status == FollowStatus.requested) {
          showVxSnackOn(messenger, 'Demande d’abonnement envoyée à @${profile.username}');
        }
      } else {
        await repository.unfollow(profile.username);
        if (mounted) setState(() => _status = FollowStatus.none);
      }
      // The feed shows what the new account did.
      ref.invalidate(feedProvider);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final suggestion = widget.suggestion;
    final profile = suggestion.profile;
    final avatar = layout.size(64, tv: 104);
    final name = profile.name.trim().isEmpty ? '@${profile.username}' : profile.name;
    final why = suggestion.compatibility != null
        ? '${suggestion.compatibility} % de goûts en commun'
        : suggestion.reason;
    return SizedBox(
      width: SuggestionCard.widthOf(layout),
      child: VxCard(
        padding: EdgeInsets.all(layout.space(VxSpace.s)),
        child: Column(
          children: [
            VxFocusable(
              borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
              semanticLabel: '$name, @${profile.username}${why.isEmpty ? '' : ', $why'}',
              onPressed: () => context.push(AccountTile.location(profile.username)),
              child: Column(
                children: [
                  AvatarTile(
                    avatarId: profile.avatar,
                    initial: ProfileHeader.initialOf(profile.name),
                    size: avatar,
                    radius: avatar / 2,
                  ),
                  SizedBox(height: layout.space(VxSpace.xs)),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                  ),
                  Text(
                    '@${profile.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                  ),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Text(
                    why,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: VxText.body(layout.captionSize, color: VxColors.textMuted),
                  ),
                ],
              ),
            ),
            const Spacer(),
            VxButton(
              label: switch (_status) {
                FollowStatus.none => 'Suivre',
                FollowStatus.requested => 'Demande envoyée',
                FollowStatus.following => 'Abonné',
              },
              kind: _status == FollowStatus.none ? VxButtonKind.primary : VxButtonKind.outline,
              dense: true,
              expand: true,
              loading: _busy,
              onPressed: _toggle,
            ),
          ],
        ),
      ),
    );
  }
}

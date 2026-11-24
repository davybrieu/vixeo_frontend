import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/paging.dart' show LoadMoreSentinel;
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../profiles/avatars.dart';
import '../social/profile_view.dart';
import '../social/social_repository.dart';
import 'inbox.dart';

/// « Notifications » (`/notifications`, in the navigation with the number of unread notifications;
/// developer's request, 21/11/2026): **everything in one list** (developer's request, 23/11/2026:
/// no separate « Activité » and « Prochains épisodes »): the follow requests to accept or decline
/// (a private account), the next episodes of the « À voir » shows (the soonest first), then what
/// happened, the most recent first: what other members did (followed the profile, liked a review,
/// commented…) and the episodes out this week. Nothing: the [EmptyState] of the « Fil
/// d'actualité ». Opening the page marks everything read. API: vixeo_backend/docs/social.md.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  static const location = '/notifications';

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  bool _markedRead = false;
  final _answering = <String>{};

  @override
  void initState() {
    super.initState();
    // Once the notifications are shown, they are read (their dots stay until the next visit).
    // After the frame: the badge (another provider) isn't changed while the pages are built.
    ref.listenManual(activityFeedProvider, (_, next) {
      final feed = next.value;
      if (feed == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markRead(feed);
      });
    }, fireImmediately: true);
  }

  Future<void> _markRead(ActivityFeedState feed) async {
    if (_markedRead) return;
    _markedRead = true;
    final unread = ref.read(unreadNotificationsProvider) > 0 || feed.items.any((item) => !item.read);
    ref.read(unreadNotificationsProvider.notifier).clear();
    if (!unread) return;
    try {
      await ref.read(inboxRepositoryProvider).markRead();
    } catch (_) {
      // Read on the next visit.
    }
  }

  Future<void> _refresh() async {
    _markedRead = false;
    ref
      ..invalidate(followRequestsProvider)
      ..invalidate(episodeCalendarProvider)
      ..invalidate(activityFeedProvider);
    await Future.wait([
      ref.read(activityFeedProvider.future),
      ref.read(episodeCalendarProvider.future),
      ref.read(followRequestsProvider.future),
    ]).catchError((_) => const <Object>[]);
  }

  Future<void> _answer(SocialProfile profile, {required bool accept}) async {
    final username = profile.username;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _answering.add(username));
    try {
      final repository = ref.read(socialRepositoryProvider);
      if (accept) {
        await repository.acceptRequest(username);
      } else {
        await repository.declineRequest(username);
      }
      if (!mounted) return;
      ref
        ..invalidate(followRequestsProvider)
        ..invalidate(activityFeedProvider)
        // My followers.
        ..invalidate(socialProfileProvider);
      showVxSnackOn(messenger, accept ? '@$username vous suit désormais' : 'Demande de @$username refusée');
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } catch (_) {
      showVxSnackOn(messenger, 'Impossible de répondre à la demande.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _answering.remove(username));
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final requestsValue = ref.watch(followRequestsProvider);
    final requests = requestsValue.value ?? const <SocialProfile>[];
    final calendar = ref.watch(episodeCalendarProvider);
    final feed = ref.watch(activityFeedProvider);
    final now = DateTime.now();
    final upcoming = [...?calendar.value?.upcoming]..sort((a, b) => a.availableAt.compareTo(b.availableAt));

    // The first element of the page takes the focus on arrival (TV).
    var focus = true;
    bool takeFocus() {
      final first = focus;
      focus = false;
      return first;
    }

    // What happened, the most recent first: the members' activity and the episodes out this week.
    final past = <({DateTime at, Widget Function(bool autofocus) row})>[
      for (final item in feed.value?.items ?? const <Activity>[])
        // A request has its row with « Accepter » / « Refuser »; a type this app doesn't know isn't shown.
        if (item.type != ActivityType.followRequest && item.type != ActivityType.unknown)
          (
            at: item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            row: (autofocus) => _ActivityTile(activity: item, now: now, autofocus: autofocus),
          ),
      for (final episode in calendar.value?.recent ?? const <ShowEpisode>[])
        (at: episode.availableAt, row: (autofocus) => _EpisodeTile(episode: episode, now: now, autofocus: autofocus)),
    ]..sort((a, b) => b.at.compareTo(a.at));

    final rows = <Widget>[
      for (final profile in requests)
        _RequestRow(
          profile: profile,
          autofocus: takeFocus(),
          busy: _answering.contains(profile.username),
          onAnswer: (accept) => _answer(profile, accept: accept),
        ),
      for (final episode in upcoming) _EpisodeTile(episode: episode, now: now, autofocus: takeFocus()),
      for (final entry in past) entry.row(takeFocus()),
    ];
    final loading = !feed.hasValue && !feed.hasError || calendar.isLoading && !calendar.hasValue;
    final failed = feed.hasError && !feed.hasValue && calendar.hasError && !calendar.hasValue;

    final Widget content;
    if (rows.isEmpty && loading) {
      content = const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    } else if (rows.isEmpty && failed) {
      content = ErrorPanel(error: feed.error!, onRetry: _refresh);
    } else if (rows.isEmpty) {
      content = const EmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'Aucune notification',
        message:
            'Les nouveaux abonnés, les J’aime et les commentaires sur vos avis et vos listes, et les prochains '
            'épisodes des séries « À voir » apparaîtront ici.',
      );
    } else {
      content = ProfileColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, row) in rows.indexed) ...[if (i > 0) SizedBox(height: layout.listGap), row],
            // 20 at a time: the next ones as the page scrolls near the end.
            if (feed.value?.hasMore ?? false)
              LoadMoreSentinel(
                onVisible: () => ref.read(activityFeedProvider.notifier).loadMore(),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (feed.hasError && !feed.hasValue || calendar.hasError && !calendar.hasValue) ...[
              SizedBox(height: layout.space(VxSpace.m)),
              Text(
                'Certaines notifications n’ont pas pu être chargées : tirez pour réessayer.',
                style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
              ),
            ],
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VxPageHeader(title: 'Notifications'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: layout.size(0, tv: 16), bottom: pageBottomPadding(context)),
                children: [content],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A member asking to follow the profile: their page, « Accepter » and « Refuser ».
class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.profile, required this.onAnswer, this.busy = false, this.autofocus = false});

  final SocialProfile profile;
  final void Function(bool accept) onAnswer;
  final bool busy;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return FocusTraversalGroup(
      policy: vxTraversalPolicy,
      child: Row(
        children: [
          Expanded(child: AccountTile(profile: profile, autofocus: autofocus)),
          SizedBox(width: layout.space(VxSpace.xs)),
          VxIconAction(
            icon: Icons.check_rounded,
            label: 'Accepter la demande de @${profile.username}',
            active: true,
            dense: true,
            onPressed: busy ? null : () => onAnswer(true),
          ),
          SizedBox(width: layout.space(VxSpace.xs)),
          VxIconAction(
            icon: Icons.close_rounded,
            label: 'Refuser la demande de @${profile.username}',
            dense: true,
            onPressed: busy ? null : () => onAnswer(false),
          ),
        ],
      ),
    );
  }
}

/// An episode of a « À voir » show, in the list: its image, the show, « Saison 2, épisode 5 ·
/// Titre » and when it comes out (« Demain à 21:00 ») or came out (« Sorti hier »). Opens the
/// show's page.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.now, this.autofocus = false});

  final ShowEpisode episode;
  final DateTime now;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final when = episodeWhen(episode.availableAt, now);
    final upcoming = episode.availableAt.isAfter(now);
    final label = episode.label;
    // The same place as an activity's dot and avatar: the rows line up.
    final dot = layout.size(8, tv: 12);
    final image = layout.size(44, tv: 72);
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: [episode.showName, if (label.isNotEmpty) label, when].join(', '),
      onPressed: () => context.push(titlePath(MediaType.tv, episode.showId)),
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            SizedBox(width: dot),
            SizedBox(width: layout.space(VxSpace.xs)),
            ClipRRect(
              borderRadius: BorderRadius.circular(image / 4),
              child: SizedBox(
                width: image,
                height: image,
                child: NetImage(url: episode.stillUrl ?? episode.backdropUrl, seed: episode.showId),
              ),
            ),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    episode.showName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                  ),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.bodySize, color: VxColors.textSoft),
                    ),
                  Text(
                    when,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(
                      layout.captionSize,
                      color: upcoming ? VxColors.accent : VxColors.textSecondary,
                      weight: upcoming ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              upcoming ? Icons.event_rounded : Icons.live_tv_rounded,
              size: layout.size(20, tv: 32),
              color: upcoming ? VxColors.accent : VxColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// What a member did: their avatar, « Max (@max) vous suit. », how long ago, a dot while unread,
/// and the poster of a liked review. Opens their page, or my review.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.now, this.autofocus = false});

  final Activity activity;
  final DateTime now;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final actor = activity.actor;
    final name = activity.actorName;
    final moderation = activity.type == ActivityType.moderation;
    final avatar = layout.size(44, tv: 72);
    final ago = activity.createdAt == null ? null : timeAgo(activity.createdAt!, now);
    final poster = activity.review?.posterUrl;
    final dot = layout.size(8, tv: 12);
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: [
        moderation ? '$name, ${activity.message}' : '$name, @${actor.username}, ${activity.message}',
        ?ago,
        if (!activity.read) 'non lue',
      ].join(', '),
      onPressed: moderation ? null : () => context.push(activity.path),
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            SizedBox(
              width: dot,
              height: dot,
              child: activity.read
                  ? null
                  : const DecoratedBox(decoration: BoxDecoration(color: VxColors.accent, shape: BoxShape.circle)),
            ),
            SizedBox(width: layout.space(VxSpace.xs)),
            if (moderation)
              Container(
                width: avatar,
                height: avatar,
                decoration: const BoxDecoration(color: VxColors.surfaceHigh, shape: BoxShape.circle),
                child: Icon(Icons.shield_outlined, size: avatar * 0.5, color: VxColors.textSoft),
              )
            else
              AvatarTile(
                avatarId: actor.avatar,
                photoUrl: actor.photoUrl,
                initial: ProfileHeader.initialOf(actor.name),
                size: avatar,
                radius: avatar / 2,
              ),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: name, style: VxText.body(layout.bodySize, weight: FontWeight.w700)),
                        TextSpan(
                          text: ' ${activity.message}',
                          style: VxText.body(layout.bodySize, color: VxColors.textSoft),
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (ago != null)
                    Text(ago, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                ],
              ),
            ),
            if (poster != null) ...[
              SizedBox(width: layout.space(VxSpace.s)),
              ClipRRect(
                borderRadius: BorderRadius.circular(VxRadius.poster / 2),
                child: SizedBox(
                  width: layout.size(36, tv: 56),
                  height: layout.size(54, tv: 84),
                  child: NetImage(url: poster, seed: activity.review!.id),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

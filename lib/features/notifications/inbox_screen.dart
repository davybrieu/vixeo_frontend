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
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../profiles/avatars.dart';
import '../social/profile_view.dart';
import '../social/social_repository.dart';
import 'inbox.dart';

/// « Notifications » (`/notifications`, between « Recherche » and « Profil » in the navigation,
/// with the number of unread notifications; developer's request, 21/11/2026): the follow requests
/// to accept or decline (a private account), the next episodes of the « À voir » shows and those
/// out this week, then what other members did (followed the profile, accepted its request, liked a
/// review). Opening the page marks everything read. API: vixeo_backend/docs/social.md.
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
    final requests = ref.watch(followRequestsProvider).value ?? const <SocialProfile>[];
    final calendar = ref.watch(episodeCalendarProvider);
    final feed = ref.watch(activityFeedProvider);
    final now = DateTime.now();
    final activity = [
      // The requests have their own section; a type this app doesn't know isn't shown.
      for (final item in feed.value?.items ?? const <Activity>[])
        if (item.type != ActivityType.followRequest && item.type != ActivityType.unknown) item,
    ];
    final upcoming = calendar.value?.upcoming ?? const <ShowEpisode>[];
    final recent = calendar.value?.recent ?? const <ShowEpisode>[];

    // The first element of the page takes the focus on arrival (TV).
    var focus = true;
    bool takeFocus() {
      final first = focus;
      focus = false;
      return first;
    }

    final gap = SizedBox(height: layout.sectionGap);
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
                children: [
                  if (requests.isNotEmpty) ...[
                    const SectionHeader('Demandes d’abonnement'),
                    ProfileColumn(
                      child: Column(
                        children: [
                          for (final (i, profile) in requests.indexed) ...[
                            if (i > 0) SizedBox(height: layout.listGap),
                            _RequestRow(
                              profile: profile,
                              autofocus: takeFocus(),
                              busy: _answering.contains(profile.username),
                              onAnswer: (accept) => _answer(profile, accept: accept),
                            ),
                          ],
                        ],
                      ),
                    ),
                    gap,
                  ],
                  const SectionHeader('Prochains épisodes'),
                  if (calendar.isLoading && !calendar.hasValue)
                    SizedBox(height: _EpisodeCard.rowHeight(context), child: const Center(child: CircularProgressIndicator()))
                  else if (calendar.hasError && !calendar.hasValue)
                    const _Message('Impossible de charger les prochains épisodes.')
                  else if (upcoming.isEmpty)
                    _Message(
                      recent.isEmpty
                          ? 'Ajoutez des séries à « À voir » : leurs prochains épisodes s’afficheront ici.'
                          : 'Aucun nouvel épisode annoncé pour les séries « À voir ».',
                    )
                  else
                    _EpisodeRow(episodes: upcoming, now: now, autofocus: takeFocus()),
                  if (recent.isNotEmpty) ...[
                    gap,
                    const SectionHeader('Sortis cette semaine'),
                    _EpisodeRow(episodes: recent, now: now, autofocus: takeFocus()),
                  ],
                  gap,
                  const SectionHeader('Activité'),
                  if (!feed.hasValue)
                    feed.hasError
                        ? const _Message('Impossible de charger les notifications.')
                        : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else if (activity.isEmpty)
                    const _Message('Quand un membre vous suit ou aime l’un de vos avis, vous le verrez ici.')
                  else
                    ProfileColumn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, item) in activity.indexed) ...[
                            if (i > 0) SizedBox(height: layout.listGap),
                            _ActivityTile(activity: item, now: now, autofocus: takeFocus()),
                          ],
                          if (feed.value!.hasMore) ...[
                            SizedBox(height: layout.space(VxSpace.m)),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: VxButton(
                                label: 'Afficher plus',
                                kind: VxButtonKind.secondary,
                                dense: true,
                                loading: feed.value!.loadingMore,
                                onPressed: () => ref.read(activityFeedProvider.notifier).loadMore(),
                              ),
                            ),
                          ],
                        ],
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

/// A sentence in place of a section's content.
class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return ProfileColumn(
      child: Text(text, style: VxText.body(layout.bodySize, color: VxColors.textSecondary)),
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

/// Episodes side by side, in a row that scrolls sideways (like the rows of the home page).
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episodes, required this.now, this.autofocus = false});

  final List<ShowEpisode> episodes;
  final DateTime now;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return SizedBox(
      height: _EpisodeCard.rowHeight(context),
      child: FocusTraversalGroup(
        policy: vxTraversalPolicy,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.space(VxSpace.xs)),
          itemCount: episodes.length,
          separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
          itemBuilder: (_, i) => _EpisodeCard(episode: episodes[i], now: now, autofocus: autofocus && i == 0),
        ),
      ),
    );
  }
}

/// An episode: its image, the show, « Saison 2, épisode 5 · Titre » and when it comes out. Opens
/// the show's page.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode, required this.now, this.autofocus = false});

  final ShowEpisode episode;
  final DateTime now;
  final bool autofocus;

  static double widthOf(Layout layout) => layout.isLarge ? layout.tv(420) : (layout.isPhone ? 240 : 280);

  static double _titleSize(Layout layout) => layout.size(15, tv: 24);

  /// The card's text under the image: the show (1 line) and two captions, at the system's text size.
  static double _textHeight(BuildContext context) {
    final layout = Layout.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return layout.space(VxSpace.xs) +
        scaler.scale(_titleSize(layout)) * 1.45 +
        2 * scaler.scale(layout.captionSize) * 1.45 +
        4;
  }

  /// Height of a row of cards, with the room of the focus ring.
  static double rowHeight(BuildContext context) {
    final layout = Layout.of(context);
    return widthOf(layout) * 9 / 16 + _textHeight(context) + 2 * layout.space(VxSpace.xs);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final width = widthOf(layout);
    final when = episodeWhen(episode.availableAt, now);
    final label = episode.label;
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: VxRadius.poster,
      semanticLabel: [episode.showName, if (label.isNotEmpty) label, when].join(', '),
      onPressed: () => context.push(titlePath(MediaType.tv, episode.showId)),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(VxRadius.poster),
              child: SizedBox(
                width: width,
                height: width * 9 / 16,
                child: NetImage(url: episode.stillUrl ?? episode.backdropUrl, seed: episode.showId),
              ),
            ),
            SizedBox(
              height: _textHeight(context),
              child: Padding(
                padding: EdgeInsets.only(top: layout.space(VxSpace.xs)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.showName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(_titleSize(layout), weight: FontWeight.w600),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                    ),
                    Text(
                      when,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.captionSize, color: VxColors.accent, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
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

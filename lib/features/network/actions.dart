import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../library/library.dart';
import '../messages/messages.dart' show ChatMember, inboxProvider, startConversation;
import '../messages/widgets.dart' show ChatAvatar, MemberSearchResults;
import '../notifications/inbox.dart' show socialAvailable;
import '../social/social_repository.dart';
import '../tmdb/review_screen.dart' show RatingSubject, ReviewScreen;
import 'network.dart';
import 'share_image.dart';

// What can be done with a publication or a member (vixeo_backend/docs/social.md,
// docs/moderation.md): send it to a friend, add a title to a list, report, block, mute.

/// One line of an action sheet.
typedef SheetAction = ({IconData icon, String label, VoidCallback onTap, bool danger});

SheetAction sheetAction(IconData icon, String label, VoidCallback onTap, {bool danger = false}) =>
    (icon: icon, label: label, onTap: onTap, danger: danger);

/// A sheet of actions under [title] (the first one has the focus: remote).
Future<void> showActionSheet(BuildContext context, {required String title, required List<SheetAction> actions}) =>
    showModalBottomSheet<void>(
      // Above the phone's tab bar.
      useRootNavigator: true,
      context: context,
      backgroundColor: VxColors.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        final layout = Layout.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(layout.space(VxSpace.l), 0, layout.space(VxSpace.l), layout.space(VxSpace.xs)),
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VxText.title(layout.size(20, tv: 32))),
              ),
              for (final (i, action) in actions.indexed)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s), vertical: 2),
                  child: VxFocusable(
                    autofocus: i == 0,
                    borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
                    semanticLabel: action.label,
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      action.onTap();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s), vertical: layout.space(VxSpace.s)),
                      child: Row(
                        children: [
                          Icon(
                            action.icon,
                            size: layout.size(22, tv: 34),
                            color: action.danger ? VxColors.dangerText : VxColors.textSoft,
                          ),
                          SizedBox(width: layout.space(VxSpace.m)),
                          Expanded(
                            child: Text(
                              action.label,
                              style: VxText.body(
                                layout.bodySize,
                                weight: FontWeight.w600,
                                color: action.danger ? VxColors.dangerText : VxColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SizedBox(height: layout.space(VxSpace.s)),
            ],
          ),
        );
      },
    );

/// Sending to a friend needs the messaging: a signed-in adult profile, not on a TV.
bool canRecommend(WidgetRef ref) => socialAvailable(ref.read(sessionProvider)) && !DeviceInfo.isTv;

/// « … » of a review: send it, see the title, share it as an image, report it.
Future<void> showReviewMenu(BuildContext context, WidgetRef ref, SocialReview review) {
  final item = review.item;
  return showActionSheet(
    context,
    title: '${review.isMine ? 'Mon avis' : 'Avis de ${review.author.name}'} : ${item.label}',
    actions: [
      sheetAction(Icons.movie_outlined, 'Voir la fiche', () => context.push(titlePath(item.mediaType, item.id))),
      if (canRecommend(ref))
        sheetAction(
          Icons.send_outlined,
          'Envoyer à un ami',
          () => recommendToFriend(context, (type: 'review', id: '${review.id}', label: 'l’avis sur ${item.label}')),
        ),
      if (!DeviceInfo.isTv)
        sheetAction(Icons.image_outlined, 'Partager en image', () => openStory(context, StoryContent.review(review))),
      if (review.isMine)
        sheetAction(
          Icons.edit_outlined,
          'Modifier mon avis',
          () => context.push(ReviewScreen.location(item.target), extra: RatingSubject.of(item)),
        )
      else ...[
        sheetAction(Icons.flag_outlined, 'Signaler l’avis', () => report(context, ref, ReportSubject.review, review.id), danger: true),
      ],
    ],
  );
}

/// « … » of a list: send it, share it as an image, change or delete it (mine), report it.
Future<void> showListMenu(BuildContext context, WidgetRef ref, SocialList list) => showActionSheet(
  context,
  title: list.title,
  actions: [
    if (canRecommend(ref))
      sheetAction(
        Icons.send_outlined,
        'Envoyer à un ami',
        () => recommendToFriend(context, (type: 'list', id: '${list.id}', label: 'la liste « ${list.title} »')),
      ),
    if (!DeviceInfo.isTv && (list.items?.isNotEmpty ?? list.itemsCount > 0))
      sheetAction(Icons.image_outlined, 'Partager en image', () => openStory(context, StoryContent.list(list))),
    if (list.isMine) ...[
      sheetAction(Icons.edit_outlined, 'Modifier la liste', () => context.push('/listes/${list.id}/modifier')),
      sheetAction(Icons.delete_outline_rounded, 'Supprimer la liste', () => deleteList(context, ref, list), danger: true),
    ] else
      sheetAction(Icons.flag_outlined, 'Signaler la liste', () => report(context, ref, ReportSubject.list, list.id), danger: true),
  ],
);

/// Deletes one of my lists, after a confirmation, then goes back.
Future<void> deleteList(BuildContext context, WidgetRef ref, SocialList list) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showVxConfirm(
    context,
    title: 'Supprimer « ${list.title} » ?',
    message: 'La liste, ses J’aime et ses commentaires seront supprimés.',
    confirm: 'Supprimer',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(networkRepositoryProvider).deleteList(list.id);
    ref.invalidate(myListsProvider);
    ref.invalidate(memberListsProvider);
    ref.invalidate(feedProvider);
    showVxSnackOn(messenger, 'Liste supprimée', icon: Icons.delete_outline_rounded);
    if (context.mounted && GoRouterState.of(context).uri.path.startsWith('/listes/${list.id}')) {
      context.canPop() ? context.pop() : context.go('/profil');
    }
  } on ApiException catch (e) {
    showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
  }
}

/// « … » of a member's page: mute (feed only), block (everywhere), report.
Future<void> showMemberMenu(BuildContext context, WidgetRef ref, SocialProfile member) => showActionSheet(
  context,
  title: '@${member.username}',
  actions: [
    if (!member.isBlocked)
      sheetAction(
        member.isMuted ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        member.isMuted ? 'Ne plus masquer de mon fil' : 'Masquer de mon fil',
        () => _mute(context, ref, member),
      ),
    sheetAction(
      Icons.block_rounded,
      member.isBlocked ? 'Débloquer' : 'Bloquer',
      () => _block(context, ref, member),
      danger: !member.isBlocked,
    ),
    sheetAction(Icons.flag_outlined, 'Signaler le compte', () => report(context, ref, ReportSubject.profile, member.id), danger: true),
  ],
);

Future<void> _mute(BuildContext context, WidgetRef ref, SocialProfile member) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(networkRepositoryProvider).mute(member.username, muted: !member.isMuted);
    ref.invalidate(socialProfileProvider(member.username));
    ref.invalidate(feedProvider);
    ref.invalidate(hiddenAccountsProvider);
    showVxSnackOn(
      messenger,
      member.isMuted ? '@${member.username} revient dans votre fil' : '@${member.username} n’apparaît plus dans votre fil',
      icon: Icons.visibility_off_outlined,
    );
  } on ApiException catch (e) {
    showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
  }
}

Future<void> _block(BuildContext context, WidgetRef ref, SocialProfile member) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!member.isBlocked) {
    final ok = await showVxConfirm(
      context,
      title: 'Bloquer @${member.username} ?',
      message:
          'Vous ne vous suivrez plus. Ni l’un ni l’autre ne pourra voir ce que l’autre publie, l’aimer, le commenter ni lui écrire. '
          'Ce compte n’est pas prévenu.',
      confirm: 'Bloquer',
      danger: true,
    );
    if (!ok) return;
  }
  try {
    await ref.read(networkRepositoryProvider).block(member.username, blocked: !member.isBlocked);
    ref.invalidate(socialProfileProvider(member.username));
    ref.invalidate(feedProvider);
    ref.invalidate(hiddenAccountsProvider);
    showVxSnackOn(
      messenger,
      member.isBlocked ? '@${member.username} est débloqué' : '@${member.username} est bloqué',
      icon: Icons.block_rounded,
    );
  } on ApiException catch (e) {
    showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
  }
}

/// Reports something to the moderation: the reason, then it is sent.
Future<void> report(BuildContext context, WidgetRef ref, ReportSubject subject, int id) async {
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(networkRepositoryProvider);
  var reasons = fallbackReportReasons;
  try {
    final fromApi = await repository.reportReasons();
    if (fromApi.isNotEmpty) reasons = fromApi;
  } catch (_) {
    // The usual reasons.
  }
  if (!context.mounted) return;
  final choice = await showVxChoice<String>(
    context,
    title: 'Pourquoi signalez-vous ce contenu ?',
    options: [for (final r in reasons) (r.reason, r.label)],
    selected: null,
  );
  final reason = choice?.$1;
  if (reason == null) return;
  try {
    await repository.report(subject, id, reason);
    showVxSnackOn(messenger, 'Merci, la modération va examiner votre signalement.', icon: Icons.flag_outlined);
  } on ApiException catch (e) {
    showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
  }
}

/// « Ajouter à une liste » (the bookmark of a title, developer's request, 23/11/2026: choose the
/// list): « À voir » first, then my lists; a press adds the title or removes it; or a new list
/// with it.
Future<void> showAddToList(BuildContext context, MediaItem title) => showModalBottomSheet<void>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  backgroundColor: VxColors.surface,
  showDragHandle: true,
  builder: (_) => _AddToListSheet(title: title),
);

class _AddToListSheet extends ConsumerStatefulWidget {
  const _AddToListSheet({required this.title});

  final MediaItem title;

  @override
  ConsumerState<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends ConsumerState<_AddToListSheet> {
  final _busy = <int>{};

  /// « À voir » is being changed.
  bool _busyToWatch = false;

  String get _item => itemIdOf(widget.title.type, widget.title.id);

  Future<void> _toggleToWatch(bool inIt) async {
    if (_busyToWatch) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyToWatch = true);
    try {
      await ref.read(libraryProvider.notifier).setFavorite(widget.title, !inIt);
      showVxSnackOn(
        messenger,
        inIt ? 'Retiré de « À voir »' : 'Ajouté à « À voir »',
        icon: inIt ? Icons.bookmark_remove_rounded : Icons.bookmark_added_rounded,
      );
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busyToWatch = false);
    }
  }

  Future<void> _toggle(SocialList list) async {
    if (_busy.contains(list.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(list.id));
    try {
      final repository = ref.read(networkRepositoryProvider);
      if (list.contains) {
        await repository.removeFromList(list.id, widget.title);
        showVxSnackOn(messenger, 'Retiré de « ${list.title} »', icon: Icons.playlist_remove_rounded);
      } else {
        await repository.addToList(list.id, _item);
        showVxSnackOn(messenger, 'Ajouté à « ${list.title} »', icon: Icons.playlist_add_check_rounded);
      }
      ref.invalidate(myListsProvider);
      ref.invalidate(listProvider(list.id));
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy.remove(list.id));
    }
  }

  void _create() {
    Navigator.of(context).pop();
    context.push(newListLocation(item: _item));
  }

  /// A line of the sheet: its state, its name and how many titles it has.
  Widget _line({
    required bool contains,
    required bool busy,
    required String title,
    required String summary,
    required VoidCallback onPressed,
    bool autofocus = false,
    IconData? icon,
  }) {
    final layout = Layout.of(context);
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: '$title, $summary${contains ? ', contient ce titre' : ''}',
      onPressed: onPressed,
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.s)),
        child: Row(
          children: [
            Icon(
              contains ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              color: contains ? VxColors.accent : VxColors.textSecondary,
              size: layout.size(24, tv: 36),
            ),
            SizedBox(width: layout.space(VxSpace.m)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: layout.size(16, tv: 26), color: VxColors.accent),
                        SizedBox(width: layout.space(VxSpace.xxs)),
                      ],
                      Flexible(child: Text(title, style: VxText.body(layout.bodySize, weight: FontWeight.w600))),
                    ],
                  ),
                  Text(summary, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                ],
              ),
            ),
            if (busy)
              SizedBox.square(
                dimension: layout.size(20, tv: 30),
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final lists = ref.watch(myListsProvider(_item));
    final library = ref.watch(libraryProvider).value;
    final inToWatch = library?.forItem(widget.title)?.isFavorite ?? false;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.space(VxSpace.l), 0, layout.space(VxSpace.l), layout.space(VxSpace.s)),
              child: Text('Ajouter « ${widget.title.title} » à une liste', style: VxText.title(layout.size(20, tv: 32))),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s)),
                children: [
                  // « À voir »: always there, first.
                  _line(
                    contains: inToWatch,
                    busy: _busyToWatch,
                    title: 'À voir',
                    summary: titleCount(library?.toWatch.length ?? 0),
                    icon: Icons.bookmark_rounded,
                    autofocus: true,
                    onPressed: () => _toggleToWatch(inToWatch),
                  ),
                  ...switch (lists) {
                    AsyncValue(:final value?) => [
                      for (final list in value)
                        _line(
                          contains: list.contains,
                          busy: _busy.contains(list.id),
                          title: list.title,
                          summary: list.summary,
                          onPressed: () => _toggle(list),
                        ),
                    ],
                    AsyncValue(:final error?) => [
                      Padding(
                        padding: EdgeInsets.all(layout.space(VxSpace.m)),
                        child: Text(
                          error is ApiException ? error.message : 'Impossible de charger vos listes.',
                          style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
                        ),
                      ),
                    ],
                    _ => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
                  },
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(layout.space(VxSpace.m)),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VxButton(
                  label: 'Nouvelle liste',
                  icon: Icons.playlist_add_rounded,
                  kind: VxButtonKind.secondary,
                  dense: true,
                  onPressed: _create,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a new list opens: a template's title, a title already in it.
String newListLocation({String? title, String? item}) {
  final query = {'titre': ?title, 'item': ?item};
  return Uri(path: '/listes/nouvelle', queryParameters: query.isEmpty ? null : query).toString();
}

/// « Envoyer à un ami »: a conversation or a member, then the card is sent in the messaging.
Future<void> recommendToFriend(BuildContext context, ShareTarget share) => showModalBottomSheet<void>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  backgroundColor: VxColors.surface,
  showDragHandle: true,
  builder: (_) => _RecommendSheet(share: share),
);

class _RecommendSheet extends ConsumerStatefulWidget {
  const _RecommendSheet({required this.share});

  final ShareTarget share;

  @override
  ConsumerState<_RecommendSheet> createState() => _RecommendSheetState();
}

class _RecommendSheetState extends ConsumerState<_RecommendSheet> {
  final _search = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send({int? conversationId, ChatMember? member, required String name}) async {
    if (_sending) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    try {
      final id = conversationId ?? await startConversation(ref, member!.username);
      await ref.read(networkRepositoryProvider).share(id, widget.share, body: _message.text);
      ref.invalidate(inboxProvider);
      navigator.pop();
      showVxSnackOn(messenger, 'Envoyé à $name', icon: Icons.send_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final query = _search.text.trim();
    final inbox = ref.watch(inboxProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.l)),
                child: Text('Envoyer ${widget.share.label}', style: VxText.title(layout.size(20, tv: 32))),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(layout.space(VxSpace.l), layout.space(VxSpace.s), layout.space(VxSpace.l), 0),
                child: TextField(
                  controller: _message,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Message (facultatif)', counterText: ''),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(layout.space(VxSpace.l)),
                child: VxSearchField(
                  controller: _search,
                  hintText: 'Écrire à un membre…',
                  onChanged: (_) {},
                  onClear: _search.clear,
                ),
              ),
              if (_sending) const LinearProgressIndicator(),
              Flexible(
                child: query.length >= 2
                    ? SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.m)),
                        child: MemberSearchResults(
                          query: query,
                          pickIcon: Icons.send_rounded,
                          pickLabel: 'Envoyer à',
                          onPick: (member) => _send(member: member, name: member.displayName),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s)),
                        children: [
                          for (final conversation in inbox.value?.conversations ?? const [])
                            if (!conversation.isPending)
                              VxFocusable(
                                borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
                                semanticLabel: 'Envoyer à ${conversation.title}',
                                onPressed: () => _send(conversationId: conversation.id, name: conversation.title),
                                child: Padding(
                                  padding: EdgeInsets.all(layout.space(VxSpace.xs)),
                                  child: Row(
                                    children: [
                                      ChatAvatar(
                                        member: conversation.participant,
                                        group: conversation.isGroup,
                                        size: layout.size(44, tv: 70),
                                      ),
                                      SizedBox(width: layout.space(VxSpace.s)),
                                      Expanded(
                                        child: Text(
                                          conversation.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: VxText.body(layout.bodySize, weight: FontWeight.w600),
                                        ),
                                      ),
                                      Icon(Icons.send_rounded, color: VxColors.accent, size: layout.size(20, tv: 30)),
                                    ],
                                  ),
                                ),
                              ),
                          if (inbox.isLoading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

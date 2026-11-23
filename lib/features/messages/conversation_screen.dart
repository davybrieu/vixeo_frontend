import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import '../network/actions.dart' show report;
import '../network/network.dart' show ReportSubject;
import '../social/profile_view.dart' show AccountTile;
import 'messages.dart';
import 'widgets.dart';

/// A conversation (`/messages/:id`, over « Messages », without the tab bar): the messages, oldest at
/// the top (the older ones load when scrolling up), a box to write and to send a photo or a video.
/// A request received is answered first (« Accepter » / « Refuser »). Read again when the API says
/// it changed (Reverb) and marked read as it is shown. A press on a photo opens it; a long press
/// (or the menu key) on a message: « Copier le texte », « Supprimer pour tout le monde » (mine).
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.id});

  final int id;

  /// Largest file sent (a video): the API refuses more.
  static const maxFileBytes = 100 * 1024 * 1024;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _answering = false;

  ConversationController get _controller => ref.read(conversationProvider(widget.id).notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  /// Near the top (the end of the reversed list): the older messages.
  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) unawaited(_controller.loadOlder());
  }

  void _toLatest() {
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
    }
  }

  void _alert(Object error, String fallback) {
    if (mounted) showVxSnack(context, errorText(error, fallback), icon: Icons.error_outline_rounded);
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _controller.send(body);
      _composer.clear();
      _toLatest();
    } catch (error) {
      _alert(error, 'Le message n’a pas pu être envoyé.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    if (_sending) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.media);
      if (file == null || !mounted) return;
      final length = file.lengthSync() ?? await file.length() ?? 0;
      if (!mounted) return;
      if (length <= 0) {
        showVxSnack(context, 'Ce fichier ne peut pas être lu.', icon: Icons.error_outline_rounded);
        return;
      }
      if (length > ConversationScreen.maxFileBytes) {
        showVxSnack(context, 'Une vidéo est limitée à 100 Mo.', icon: Icons.error_outline_rounded);
        return;
      }
      setState(() => _sending = true);
      await _controller.attach(stream: file.readAsByteStream, length: length, filename: file.name);
      _toLatest();
    } catch (error) {
      _alert(error, 'Le fichier n’a pas pu être envoyé.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _answer({required bool accept}) async {
    setState(() => _answering = true);
    try {
      if (accept) {
        await _controller.accept();
      } else {
        await ref.read(messagesRepositoryProvider).decline(widget.id);
        if (!mounted) return;
        ref.invalidate(inboxProvider);
        unawaited(ref.read(unreadMessagesProvider.notifier).refresh(force: true));
        showVxSnack(context, 'Demande refusée');
        _leave();
      }
    } catch (error) {
      _alert(error, 'Impossible de répondre à la demande.');
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  void _leave() => context.canPop() ? context.pop() : context.go('/messages');

  Future<void> _messageActions(ChatMessage message, {required bool mine}) async {
    final choice = await showVxChoice<String>(
      context,
      title: 'Message',
      options: [
        if (message.body.trim().isNotEmpty) ('copy', 'Copier le texte'),
        if (mine) ('delete', 'Supprimer pour tout le monde'),
        // Another member's message: to the moderation (docs/moderation.md).
        if (!mine) ('report', 'Signaler le message'),
      ],
      selected: null,
    );
    if (!mounted) return;
    switch (choice) {
      case ('copy',):
        await Clipboard.setData(ClipboardData(text: message.body));
        if (mounted) showVxSnack(context, 'Texte copié');
      case ('delete',):
        final ok = await showVxConfirm(
          context,
          title: 'Supprimer ce message ?',
          message: 'Il sera supprimé pour tous les participants.',
          confirm: 'Supprimer',
          danger: true,
        );
        if (!ok) return;
        try {
          await _controller.delete(message.id);
          if (mounted) showVxSnack(context, 'Message supprimé');
        } catch (error) {
          _alert(error, 'Le message n’a pas pu être supprimé.');
        }
      case ('report',):
        await report(context, ref, ReportSubject.message, message.id);
    }
  }

  /// A direct conversation: the member's page, « Bloquer » / « Débloquer ».
  Future<void> _options(ConversationPage page) async {
    final member = page.participant;
    if (member == null) return;
    final choice = await showVxChoice<String>(
      context,
      title: member.displayName,
      options: [('profile', 'Voir le profil'), page.blocked ? ('unblock', 'Débloquer') : ('block', 'Bloquer')],
      selected: null,
    );
    if (!mounted || choice == null) return;
    switch (choice.$1) {
      case 'profile':
        unawaited(context.push(AccountTile.location(member.username)));
      case 'block':
        final ok = await showVxConfirm(
          context,
          title: 'Bloquer @${member.username} ?',
          message: 'Vous ne pourrez plus vous écrire, ni l’un ni l’autre. Vous pourrez le débloquer ici.',
          confirm: 'Bloquer',
          danger: true,
        );
        if (ok) await _setBlocked(member, blocked: true);
      case 'unblock':
        await _setBlocked(member, blocked: false);
    }
  }

  Future<void> _setBlocked(ChatMember member, {required bool blocked}) async {
    try {
      final username = member.username;
      await _controller.change(
        (repository) => blocked ? repository.block(username) : repository.unblock(username),
      );
      if (mounted) showVxSnack(context, blocked ? '@$username est bloqué' : '@$username est débloqué');
    } catch (error) {
      _alert(error, 'Impossible de modifier le blocage.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final state = ref.watch(conversationProvider(widget.id));
    final me = ref.watch(sessionProvider.select((s) => s.profile?.id));
    final data = state.value;
    final page = data?.page;

    return Scaffold(
      backgroundColor: VxColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              page: page,
              onTitle: page == null
                  ? null
                  : page.isGroup
                  ? () => context.push(groupSettingsLocation(widget.id))
                  : switch (page.participant) {
                      final member? => () => context.push(AccountTile.location(member.username)),
                      null => null,
                    },
              onOptions: page == null
                  ? null
                  : page.isGroup
                  ? () => context.push(groupSettingsLocation(widget.id))
                  : () => _options(page),
            ),
            Expanded(
              child: switch (state) {
                AsyncValue(value: final data?) => _MessageList(
                  state: data,
                  me: me,
                  controller: _scroll,
                  onActions: _messageActions,
                ),
                AsyncValue(:final error?) => ErrorPanel(
                  error: error,
                  onRetry: () => ref.invalidate(conversationProvider(widget.id)),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
            if (page != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.gutter,
                  layout.space(VxSpace.xs),
                  layout.gutter,
                  layout.space(VxSpace.s),
                ),
                child: page.isRequest
                    ? _Notice(
                        text:
                            '${page.participant?.displayName ?? 'Ce membre'} souhaite vous écrire. '
                            'Acceptez pour répondre.',
                        actions: [
                          VxButton(
                            label: 'Refuser',
                            kind: VxButtonKind.outline,
                            dense: true,
                            onPressed: _answering ? null : () => _answer(accept: false),
                          ),
                          VxButton(
                            label: 'Accepter',
                            dense: true,
                            loading: _answering,
                            onPressed: _answering ? null : () => _answer(accept: true),
                          ),
                        ],
                      )
                    : page.blocked
                    ? _Notice(
                        text: 'Vous avez bloqué ce membre.',
                        actions: [
                          VxButton(
                            label: 'Débloquer',
                            kind: VxButtonKind.secondary,
                            dense: true,
                            onPressed: () => _setBlocked(page.participant!, blocked: false),
                          ),
                        ],
                      )
                    : _Composer(
                        controller: _composer,
                        sending: _sending,
                        // A request not accepted yet: text only (the API refuses files until then).
                        onAttach: page.isPending ? null : _attach,
                        onSend: _send,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Back, the avatar and the name (a press: the member's page, or « Gérer le groupe »; the focus
/// on arrival), then the options.
class _Header extends StatelessWidget {
  const _Header({required this.page, required this.onTitle, required this.onOptions});

  final ConversationPage? page;
  final VoidCallback? onTitle;
  final VoidCallback? onOptions;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final page = this.page;
    final avatar = layout.size(40, tv: 64);
    final subtitle = page == null
        ? ''
        : page.isGroup
        ? '${page.participants.length + 1} membres'
        : page.isPending && !page.isRequest
        ? 'Demande envoyée'
        : '@${page.participant?.username ?? ''}';
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.xs), layout.gutter, layout.space(VxSpace.xs)),
      child: Row(
        children: [
          const VxBackButton(),
          SizedBox(width: layout.space(VxSpace.s)),
          Expanded(
            child: VxFocusable(
              autofocus: true,
              borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
              focusScale: 1.02,
              semanticLabel: page == null ? 'Conversation' : '${page.title}, $subtitle',
              onPressed: onTitle,
              child: Padding(
                padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
                child: Row(
                  children: [
                    ChatAvatar(member: page?.participant, group: page?.isGroup ?? false, size: avatar),
                    SizedBox(width: layout.space(VxSpace.s)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            page?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.title(layout.sectionTitleSize),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onOptions != null) ...[
            SizedBox(width: layout.space(VxSpace.xs)),
            VxIconAction(
              icon: page?.isGroup ?? false ? Icons.tune_rounded : Icons.more_horiz_rounded,
              label: page?.isGroup ?? false ? 'Gérer le groupe' : 'Options de la conversation',
              dense: true,
              onPressed: onOptions,
            ),
          ],
        ],
      ),
    );
  }
}

/// The messages, newest at the bottom (a reversed list: it opens on the latest), a day label above
/// the first message of each day, the sender's name above a run of messages in a group.
class _MessageList extends StatelessWidget {
  const _MessageList({required this.state, required this.me, required this.controller, required this.onActions});

  final ConversationState state;
  final int? me;
  final ScrollController controller;
  final Future<void> Function(ChatMessage message, {required bool mine}) onActions;

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final messages = state.messages;
    final page = state.page;
    if (messages.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: page.isPending && !page.isRequest ? 'Demande envoyée' : 'Aucun message',
        message: page.isPending && !page.isRequest
            ? 'Vous pourrez envoyer des photos et des vidéos une fois la demande acceptée.'
            : 'Écrivez le premier message.',
      );
    }
    final members = {for (final member in page.participants) member.id: member};
    final now = DateTime.now();
    final loader = state.hasMore || state.loadingOlder;

    return FocusTraversalGroup(
      policy: vxTraversalPolicy,
      child: ListView.builder(
        controller: controller,
        reverse: true,
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.s), layout.gutter, layout.space(VxSpace.s)),
        itemCount: messages.length + (loader ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return Padding(
              padding: EdgeInsets.all(layout.space(VxSpace.m)),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          // Index 0 is the bottom of the reversed list: the latest message.
          final i = messages.length - 1 - index;
          final message = messages[i];
          final previous = i > 0 ? messages[i - 1] : null;
          final next = i + 1 < messages.length ? messages[i + 1] : null;
          final mine = message.senderId == me;
          final newDay = previous == null || !_sameDay(previous.createdAt, message.createdAt);
          final firstOfRun = newDay || previous.senderId != message.senderId;
          final lastOfRun =
              next == null || next.senderId != message.senderId || !_sameDay(next.createdAt, message.createdAt);
          final createdAt = message.createdAt;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (newDay && createdAt != null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.s)),
                  child: Text(
                    messageDay(createdAt, now),
                    textAlign: TextAlign.center,
                    style: VxText.body(layout.captionSize, weight: FontWeight.w600, color: VxColors.textSecondary),
                  ),
                ),
              _MessageBubble(
                message: message,
                mine: mine,
                senderName: page.isGroup && !mine && firstOfRun
                    ? (members[message.senderId]?.displayName ?? 'Ancien membre')
                    : null,
                showTime: lastOfRun,
                read: mine && message.readBy.any((id) => id != me),
                onActions: () => onActions(message, mine: mine),
              ),
              SizedBox(height: lastOfRun ? layout.space(VxSpace.s) : layout.space(VxSpace.xxs)),
            ],
          );
        },
      ),
    );
  }
}

/// A message: on the right in green for mine, on the left for the others; its photo or video; under
/// the last one of a run, its time (and ✓✓ once read, for mine).
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showTime,
    required this.read,
    required this.onActions,
    this.senderName,
  });

  final ChatMessage message;
  final bool mine;
  final bool showTime;
  final bool read;
  final VoidCallback onActions;
  final String? senderName;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final radius = layout.size(18, tv: 28);
    final body = message.body.trim();
    final attachment = message.attachments.firstOrNull;
    final createdAt = message.createdAt;
    final time = createdAt == null ? '' : hourMinute(createdAt);
    // Copy, delete (mine) or report (another member's).
    final canAct = !message.deleted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(constraints.maxWidth * (layout.isPhone ? 0.8 : 0.6), layout.size(520, tv: 900));
        final bubble = Container(
          padding: attachment != null && body.isEmpty
              ? EdgeInsets.all(layout.space(VxSpace.xxs))
              : EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s), vertical: layout.space(VxSpace.xs)),
          decoration: BoxDecoration(
            color: mine ? VxColors.accent.withValues(alpha: 0.16) : VxColors.surfaceHigh,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachment != null && !message.deleted) _AttachmentView(attachment: attachment, width: maxWidth),
              if (message.shared case final shared? when !message.deleted) ...[
                _SharedCardView(card: shared),
                if (body.isNotEmpty) SizedBox(height: layout.space(VxSpace.xs)),
              ],
              if (body.isNotEmpty)
                Text(
                  body,
                  style: message.deleted
                      ? VxText.body(layout.bodySize, color: VxColors.textMuted).copyWith(fontStyle: FontStyle.italic)
                      : VxText.body(layout.bodySize),
                ),
            ],
          ),
        );
        final shared = message.deleted ? null : message.shared;
        final label = [
          ?senderName,
          if (attachment != null && !message.deleted) attachment.isImage ? 'Photo' : 'Vidéo',
          if (shared != null) '${switch (shared.kind) {
            'review' => 'Avis',
            'list' => 'Liste',
            _ => 'Titre',
          }} partagé : ${shared.title}',
          if (body.isNotEmpty) body,
          if (time.isNotEmpty) time,
          if (read) 'lu',
        ].join(', ');

        return Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderName != null)
              Padding(
                padding: EdgeInsets.only(left: radius / 2, bottom: layout.space(VxSpace.xxs)),
                child: Text(
                  senderName!,
                  style: VxText.body(layout.captionSize, weight: FontWeight.w600, color: VxColors.textSecondary),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: VxFocusable(
                borderRadius: radius,
                focusScale: 1.02,
                semanticLabel: label,
                onPressed: shared != null
                    ? () => context.push(shared.path)
                    : attachment != null && attachment.isImage && !message.deleted
                    ? () => _openImage(context, attachment)
                    : null,
                onLongPress: canAct ? onActions : null,
                child: bubble,
              ),
            ),
            if (showTime && time.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: layout.space(VxSpace.xxs), left: radius / 2, right: radius / 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                    if (mine) ...[
                      SizedBox(width: layout.space(VxSpace.xxs)),
                      Icon(
                        read ? Icons.done_all_rounded : Icons.done_rounded,
                        size: layout.captionSize * 1.2,
                        color: read ? VxColors.accent : VxColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A title, a review or a list sent in a message: its poster(s), its title, a line (« Film · 1999 »,
/// « Avis de @lea · ★ 8/10 », « Liste · 10 titres »), the beginning of a review. A press on the
/// bubble opens it.
class _SharedCardView extends StatelessWidget {
  const _SharedCardView({required this.card});

  final SharedCard card;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final poster = layout.size(52, tv: 84);
    final radius = layout.size(8, tv: 12);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (card.images.isEmpty)
          Container(
            width: poster,
            height: poster * 1.5,
            decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(radius)),
            child: Icon(
              card.kind == 'list' ? Icons.playlist_play_rounded : Icons.movie_outlined,
              color: VxColors.textMuted,
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: SizedBox(
              width: poster,
              height: poster * 1.5,
              child: NetImage(url: card.images.first, seed: card.title.hashCode),
            ),
          ),
        SizedBox(width: layout.space(VxSpace.s)),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: VxText.body(layout.bodySize, weight: FontWeight.w700),
              ),
              if ((card.subtitle ?? '').isNotEmpty)
                Text(card.subtitle!, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
              if ((card.excerpt ?? '').isNotEmpty) ...[
                SizedBox(height: layout.space(VxSpace.xxs)),
                Text(
                  '« ${card.excerpt} »',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(layout.captionSize, color: VxColors.textSoft),
                ),
              ],
              SizedBox(height: layout.space(VxSpace.xxs)),
              Text(
                switch (card.kind) {
                  'review' => 'Lire l’avis',
                  'list' => 'Voir la liste',
                  _ => 'Voir la fiche',
                },
                style: VxText.body(layout.captionSize, weight: FontWeight.w700, color: VxColors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A photo of a message, downloaded with the token, at the bubble's width; a video: its icon,
/// its name and its size.
class _AttachmentView extends ConsumerWidget {
  const _AttachmentView({required this.attachment, required this.width});

  final ChatAttachment attachment;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final radius = layout.size(14, tv: 22);
    if (!attachment.isImage) {
      return Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xs)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, size: layout.size(28, tv: 44), color: VxColors.textSecondary),
            SizedBox(width: layout.space(VxSpace.xs)),
            Flexible(
              child: Text(
                'Vidéo · ${fileSize(attachment.size)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VxText.body(layout.bodySize),
              ),
            ),
          ],
        ),
      );
    }
    final image = ref.watch(attachmentBytesProvider(attachment.url));
    final bytes = image.value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: bytes == null
          ? SizedBox(
              width: width,
              height: width * 0.75,
              child: ColoredBox(
                color: VxColors.surface,
                child: Center(
                  child: image.hasError
                      ? Icon(Icons.broken_image_outlined, size: layout.size(32, tv: 48), color: VxColors.textMuted)
                      : const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
                ),
              ),
            )
          : Image.memory(
              bytes,
              width: width,
              fit: BoxFit.cover,
              // Decoded at the size shown, not at the photo's.
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
              gaplessPlayback: true,
            ),
    );
  }
}

/// A photo in full screen, to zoom in; back closes it.
Future<void> _openImage(BuildContext context, ChatAttachment attachment) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (dialogContext) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Consumer(
      builder: (context, ref, _) {
        final Uint8List? bytes = ref.watch(attachmentBytesProvider(attachment.url)).value;
        final layout = Layout.of(context);
        return Stack(
          children: [
            Positioned.fill(
              child: bytes == null
                  ? const Center(child: CircularProgressIndicator())
                  : InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(bytes))),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + layout.space(VxSpace.s),
              left: layout.gutter,
              child: VxBackButton(onPressed: () => Navigator.of(dialogContext).pop()),
            ),
          ],
        );
      },
    ),
  ),
);

/// The box to write, the paperclip (photo or video) and « Envoyer ».
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onAttach, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (onAttach != null) ...[
          VxIconAction(
            icon: Icons.attach_file_rounded,
            label: 'Envoyer une photo ou une vidéo',
            dense: true,
            onPressed: sending ? null : onAttach,
          ),
          SizedBox(width: layout.space(VxSpace.xs)),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: VxText.body(layout.size(16, tv: 24)),
            decoration: InputDecoration(
              hintText: 'Écrire un message…',
              hintStyle: VxText.body(layout.size(16, tv: 24), color: VxColors.textMuted),
              contentPadding: EdgeInsets.symmetric(
                horizontal: layout.space(VxSpace.m),
                vertical: layout.space(VxSpace.s),
              ),
            ),
          ),
        ),
        SizedBox(width: layout.space(VxSpace.xs)),
        sending
            ? SizedBox.square(
                dimension: VxIconAction.sizeOf(layout, dense: true),
                child: const Center(
                  child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                ),
              )
            : VxIconAction(icon: Icons.send_rounded, label: 'Envoyer', active: true, dense: true, onPressed: onSend),
      ],
    );
  }
}

/// Instead of the box to write: a sentence and its buttons (a request to answer, a blocked member).
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center, style: VxText.body(layout.bodySize, color: VxColors.textSoft)),
        SizedBox(height: layout.space(VxSpace.s)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: layout.space(VxSpace.s),
          runSpacing: layout.space(VxSpace.xs),
          children: actions,
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import 'messages.dart';
import 'widgets.dart';

/// « Messages » (`/messages`, in the navigation; vixeo_backend/docs/messagerie.md): a search to
/// write to a member, « Créer un groupe », the requests received (accept or decline), then the
/// conversations, the most recent first, with their last message and unread messages. Not for a
/// guest nor a child's profile (the route leads home).
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  static const location = '/messages';

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _search = TextEditingController();
  Timer? _typing;
  String _query = '';
  final _answering = <int>{};

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The search waits for the typing to pause (not one request per letter).
  void _onSearch(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  void _clearSearch() {
    _typing?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  Future<void> _write(ChatMember member) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await startConversation(ref, member.username);
      if (!mounted) return;
      _clearSearch();
      unawaited(context.push(conversationLocation(id)));
    } catch (error) {
      showVxSnackOn(
        messenger,
        errorText(error, 'Impossible d’écrire à ce membre.'),
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _answer(MessageRequest request, {required bool accept}) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = request.conversationId;
    setState(() => _answering.add(id));
    try {
      final repository = ref.read(messagesRepositoryProvider);
      if (accept) {
        await repository.accept(id);
      } else {
        await repository.decline(id);
      }
      if (!mounted) return;
      ref.invalidate(inboxProvider);
      if (accept) {
        unawaited(context.push(conversationLocation(id)));
      } else {
        showVxSnackOn(messenger, 'Demande refusée');
      }
    } catch (error) {
      showVxSnackOn(
        messenger,
        errorText(error, 'Impossible de répondre à la demande.'),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _answering.remove(id));
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(inboxProvider);
    await ref.read(inboxProvider.future).catchError((_) => const Inbox());
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final me = ref.watch(sessionProvider.select((s) => s.profile?.id));
    final inbox = ref.watch(inboxProvider);

    // The first element of the list takes the focus on arrival (TV; never the search field, which
    // would open the keyboard).
    var focus = true;
    bool takeFocus() {
      final first = focus;
      focus = false;
      return first;
    }

    final List<Widget> content;
    if (_query.length >= 2) {
      content = [MemberSearchResults(query: _query, onPick: _write)];
    } else {
      content = switch (inbox) {
        AsyncValue(value: final data?) => [
          if (data.requests.isNotEmpty) ...[
            SectionHeader('Demandes de message', padding: EdgeInsets.only(bottom: layout.titleGap)),
            for (final request in data.requests) ...[
              _RequestTile(
                request: request,
                autofocus: takeFocus(),
                busy: _answering.contains(request.conversationId),
                onOpen: () => context.push(conversationLocation(request.conversationId)),
                onAccept: () => _answer(request, accept: true),
                onDecline: () => _answer(request, accept: false),
              ),
              SizedBox(height: layout.listGap),
            ],
            SizedBox(height: layout.sectionGap - layout.listGap),
          ],
          if (data.conversations.isEmpty && data.requests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.forum_outlined,
                title: 'Aucune conversation',
                message: 'Recherchez un membre pour lui écrire, ou créez un groupe.',
              ),
            ),
          for (final (i, conversation) in data.conversations.indexed) ...[
            if (i > 0) SizedBox(height: layout.space(VxSpace.xxs)),
            _ConversationTile(
              conversation: conversation,
              mine: conversation.lastSenderId == me,
              autofocus: takeFocus(),
              onPressed: () => context.push(conversationLocation(conversation.id)),
            ),
          ],
        ],
        AsyncValue(:final error?) => [ErrorPanel(error: error, onRetry: () => ref.invalidate(inboxProvider))],
        _ => [
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      };
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: 'Messages',
            search: Row(
              children: [
                Expanded(
                  child: VxSearchField(
                    controller: _search,
                    fontSize: layout.size(16, tv: 24),
                    hintText: 'Écrire à un membre…',
                    onChanged: _onSearch,
                    onClear: _clearSearch,
                  ),
                ),
                SizedBox(width: layout.space(VxSpace.s)),
                VxIconAction(
                  icon: Icons.group_add_outlined,
                  label: 'Créer un groupe',
                  onPressed: () => context.push(newGroupLocation),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pageContentPadding(context),
                children: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A conversation: avatar (or the group's icon), name, last message (« Vous : … » when it is
/// mine), its date and the number of unread messages.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.mine,
    required this.onPressed,
    this.autofocus = false,
  });

  final ConversationSummary conversation;
  final bool mine;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(52, tv: 84);
    final unread = conversation.unreadCount;
    final last = conversation.lastMessage?.trim() ?? '';
    final preview = conversation.isPending
        ? 'Demande envoyée'
        : last.isEmpty
        ? (conversation.lastSenderId == null ? 'Aucun message' : 'Photo ou vidéo')
        : (mine ? 'Vous : $last' : last);
    final updated = conversation.updatedAt;
    final when = updated == null ? '' : conversationTime(updated, DateTime.now());
    final label = [
      conversation.title,
      if (unread > 0) unread == 1 ? '1 message non lu' : '$unread messages non lus',
      preview,
      if (when.isNotEmpty) when,
    ].join(', ');

    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: label,
      autofocus: autofocus,
      onPressed: onPressed,
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xs)),
        child: Row(
          children: [
            ChatAvatar(member: conversation.participant, group: conversation.isGroup, size: avatar),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
                  ),
                  SizedBox(height: layout.space(VxSpace.xxs) / 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(
                      layout.size(14, tv: 20),
                      weight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                      color: unread > 0 ? VxColors.text : VxColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: layout.space(VxSpace.xs)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(when, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                if (unread > 0) ...[SizedBox(height: layout.space(VxSpace.xxs)), UnreadBadge(count: unread)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A request received: who sent it, its first message, « Accepter » ✓ and « Refuser » ✕. A press
/// on the rest opens the conversation (to read it before answering).
class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
    this.autofocus = false,
  });

  final MessageRequest request;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final sender = request.sender;
    final name = sender?.displayName ?? 'Un membre';
    final preview = request.preview?.trim() ?? '';
    return Row(
      children: [
        Expanded(
          child: sender == null
              ? Text(name, style: VxText.body(layout.bodySize))
              : MemberRow(
                  member: sender,
                  subtitle: preview.isEmpty ? 'Souhaite vous écrire' : preview,
                  semanticLabel: 'Demande de $name${preview.isEmpty ? '' : ' : $preview'}. Ouvrir la conversation',
                  autofocus: autofocus,
                  onPressed: onOpen,
                ),
        ),
        SizedBox(width: layout.space(VxSpace.xs)),
        VxIconAction(
          icon: Icons.check_rounded,
          label: 'Accepter la demande de $name',
          active: true,
          dense: true,
          onPressed: busy ? null : onAccept,
        ),
        SizedBox(width: layout.space(VxSpace.xs)),
        VxIconAction(
          icon: Icons.close_rounded,
          label: 'Refuser la demande de $name',
          dense: true,
          onPressed: busy ? null : onDecline,
        ),
      ],
    );
  }
}

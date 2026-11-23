import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart' show uiScale;
import '../auth/session.dart';
import '../notifications/inbox.dart' show socialAvailable;
import '../tmdb/rating_form.dart' show SpoilerSwitch;
import 'actions.dart';
import 'network.dart';
import 'widgets.dart';

/// The comments of a review or a list (vixeo_backend/docs/social.md): the conversation of the
/// social network. The latest ones, older ones on demand, then the field to write one (with
/// « Contient des spoilers »). On a TV, they are read only.
class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({super.key, required this.subject, this.onCountChanged});

  final CommentSubject subject;

  /// A comment was added (+1) or deleted (−1).
  final ValueChanged<int>? onCountChanged;

  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _field = TextEditingController();
  bool _spoilers = false;
  bool _sending = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _field.text.trim();
    if (text.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(commentsProvider(widget.subject).notifier).add(text, spoilers: _spoilers);
      _field.clear();
      setState(() => _spoilers = false);
      widget.onCountChanged?.call(1);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadOlder() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commentsProvider(widget.subject).notifier).loadOlder();
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _menu(SocialComment comment) => showActionSheet(
    context,
    title: 'Commentaire de ${comment.author.name}',
    actions: [
      if (comment.canDelete)
        sheetAction(Icons.delete_outline_rounded, 'Supprimer le commentaire', () => _delete(comment), danger: true),
      if (!comment.isMine)
        sheetAction(
          Icons.flag_outlined,
          'Signaler le commentaire',
          () => report(context, ref, ReportSubject.comment, comment.id),
          danger: true,
        ),
    ],
  );

  Future<void> _delete(SocialComment comment) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showVxConfirm(context, title: 'Supprimer ce commentaire ?', confirm: 'Supprimer', danger: true);
    if (!ok) return;
    try {
      await ref.read(commentsProvider(widget.subject).notifier).delete(comment);
      widget.onCountChanged?.call(-1);
      showVxSnackOn(messenger, 'Commentaire supprimé', icon: Icons.delete_outline_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final comments = ref.watch(commentsProvider(widget.subject));
    final canWrite = socialAvailable(ref.watch(sessionProvider)) && !DeviceInfo.isTv;
    final value = comments.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Commentaires', style: VxText.title(layout.sectionTitleSize)),
        SizedBox(height: layout.titleGap),
        if (value == null)
          comments.hasError
              ? Text('Impossible de charger les commentaires.', style: VxText.body(layout.bodySize, color: VxColors.textSecondary))
              : const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else ...[
          if (value.hasMore)
            Padding(
              padding: EdgeInsets.only(bottom: layout.listGap),
              child: VxButton(
                label: 'Afficher les commentaires précédents',
                kind: VxButtonKind.outline,
                dense: true,
                onPressed: _loadOlder,
              ),
            ),
          if (value.comments.isEmpty)
            Text(
              canWrite ? 'Aucun commentaire pour l’instant : lancez la conversation.' : 'Aucun commentaire pour l’instant.',
              style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
            ),
          for (final comment in value.comments)
            Padding(
              padding: EdgeInsets.only(bottom: layout.listGap),
              child: _CommentTile(comment: comment, onMenu: () => _menu(comment)),
            ),
        ],
        SizedBox(height: layout.space(VxSpace.s)),
        if (canWrite) ...[
          TextField(
            controller: _field,
            minLines: 1,
            maxLines: 5,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            style: VxText.body(layout.bodySize),
            decoration: const InputDecoration(hintText: 'Ajouter un commentaire…', counterText: ''),
          ),
          SizedBox(height: layout.space(VxSpace.xs)),
          Row(
            children: [
              Expanded(
                child: SpoilerSwitch(
                  value: _spoilers,
                  scale: uiScale(context),
                  onChanged: (value) => setState(() => _spoilers = value),
                ),
              ),
              SizedBox(width: layout.space(VxSpace.s)),
              VxButton(label: 'Publier', icon: Icons.send_rounded, dense: true, loading: _sending, onPressed: _send),
            ],
          ),
        ] else if (DeviceInfo.isTv)
          Text(
            'Commentez depuis l’appli Vixeo de votre téléphone.',
            style: VxText.body(layout.captionSize, color: VxColors.textMuted),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onMenu});

  final SocialComment comment;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final menu = comment.canDelete || !comment.isMine;
    return Container(
      padding: EdgeInsets.all(layout.space(VxSpace.s)),
      decoration: BoxDecoration(
        color: VxColors.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(layout.size(VxRadius.button, tv: VxRadius.buttonTv)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberLine(
            profile: comment.author,
            at: comment.createdAt,
            trailing: menu ? MoreButton(label: 'Options du commentaire', onPressed: onMenu) : null,
          ),
          SizedBox(height: layout.space(VxSpace.xs)),
          SpoilerText(text: comment.body, spoilers: comment.spoilers && !comment.isMine),
        ],
      ),
    );
  }
}

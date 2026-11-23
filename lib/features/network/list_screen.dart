import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../messages/widgets.dart' show errorText;
import 'actions.dart';
import 'comments.dart';
import 'network.dart';
import 'share_image.dart';
import 'title_picker.dart';
import 'widgets.dart';

/// A list or a top 10 (`/listes/:id`, vixeo_backend/docs/social.md): its title, its author, its
/// description, its titles (numbered for a top 10), « J'aime », then its comments. Mine:
/// « Modifier ».
class ListDetailsScreen extends ConsumerStatefulWidget {
  const ListDetailsScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ListDetailsScreen> createState() => _ListDetailsScreenState();
}

class _ListDetailsScreenState extends ConsumerState<ListDetailsScreen> {
  int _comments = 0;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final state = ref.watch(listProvider(widget.id));
    final list = state.value;
    if (list == null) {
      return NetworkPage(
        title: 'Liste',
        children: [NetworkLoading(error: state.error, onRetry: () => ref.invalidate(listProvider(widget.id)))],
      );
    }
    final titles = list.items ?? const [];
    final count = list.commentsCount + _comments;
    final description = list.description?.trim() ?? '';
    return NetworkPage(
      title: list.title,
      actions: [
        if (list.isMine)
          VxIconAction(
            icon: Icons.edit_outlined,
            label: 'Modifier la liste',
            dense: true,
            onPressed: () => context.push(ListEditorScreen.editLocation(list.id)),
          ),
        VxIconAction(
          icon: Icons.more_horiz_rounded,
          label: 'Options de la liste',
          dense: true,
          onPressed: () => showListMenu(context, ref, list),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(listProvider(widget.id));
        ref.invalidate(commentsProvider((list: true, id: widget.id)));
        setState(() => _comments = 0);
      },
      children: [
        Wrap(
          spacing: layout.space(VxSpace.xs),
          runSpacing: layout.space(VxSpace.xs),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (list.kind == ListKind.top) const VxBadge('TOP 10', accent: true),
            Text(list.summary, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
          ],
        ),
        SizedBox(height: layout.space(VxSpace.s)),
        MemberLine(profile: list.author, at: list.updatedAt),
        if (description.isNotEmpty) ...[
          SizedBox(height: layout.space(VxSpace.s)),
          Text(description, style: VxText.body(layout.bodySize, color: VxColors.textSoft, height: 1.45)),
        ],
        SizedBox(height: layout.space(VxSpace.xs)),
        Row(
          children: [
            ListLikeButton(list: list),
            CountAction(
              icon: Icons.mode_comment_outlined,
              count: count,
              label: '$count ${count > 1 ? 'commentaires' : 'commentaire'}',
            ),
            const Spacer(),
            if (!DeviceInfo.isTv && titles.isNotEmpty)
              CountAction(
                icon: Icons.ios_share_rounded,
                count: 0,
                label: 'Partager en image',
                onPressed: () => openStory(context, StoryContent.list(list)),
              ),
          ],
        ),
        SizedBox(height: layout.sectionGap),
        if (titles.isEmpty)
          EmptyState(
            icon: Icons.playlist_add_rounded,
            title: 'Liste vide',
            message: list.isMine ? 'Ajoutez des films et des séries avec « Modifier ».' : null,
          )
        else
          NumberedPosters(titles: titles, numbered: list.kind == ListKind.top),
        SizedBox(height: layout.sectionGap),
        CommentsSection(
          subject: (list: true, id: widget.id),
          onCountChanged: (delta) => setState(() => _comments += delta),
        ),
      ],
    );
  }
}

/// « Nouvelle liste », « Nouveau top 10 » or « Modifier la liste » (`/listes/nouvelle`,
/// `/listes/:id/modifier`): title (or a ready-made one: « Mon top 10 de 2026 »…), description,
/// top 10 or list, and the titles in order (« monter », « descendre », « retirer » buttons rather
/// than drag and drop: they work with a remote). [item] (`movie:550`): a title to start with
/// (« Ajouter à une liste » → « Nouvelle liste »).
class ListEditorScreen extends ConsumerStatefulWidget {
  const ListEditorScreen({super.key, this.id, this.kind = ListKind.list, this.title, this.item});

  final int? id;
  final ListKind kind;
  final String? title;
  final String? item;

  static const newLocation = '/listes/nouvelle';

  static String editLocation(int id) => '/listes/$id/modifier';

  @override
  ConsumerState<ListEditorScreen> createState() => _ListEditorScreenState();
}

class _ListEditorScreenState extends ConsumerState<ListEditorScreen> {
  late final _title = TextEditingController(text: widget.title ?? '');
  final _description = TextEditingController();
  late ListKind _kind = widget.kind;
  final _items = <MediaItem>[];
  bool _loaded = false;
  bool _saving = false;
  Object? _error;

  bool get _editing => widget.id != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_editing) {
        final list = await ref.read(networkRepositoryProvider).list(widget.id!);
        _title.text = list.title;
        _description.text = list.description ?? '';
        _kind = list.kind;
        _items.addAll(list.items ?? const []);
      } else if (widget.item case final item?) {
        final parts = item.split(':');
        final id = int.tryParse(parts.length == 2 ? parts[1] : '');
        if (id != null) {
          final titles = await ref
              .read(catalogRepositoryProvider)
              .titlesById([(type: MediaType.parse(parts[0]), id: id)]);
          _items.addAll(titles.take(1));
        }
      }
      if (mounted) setState(() => _loaded = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loaded = !_editing;
        });
      }
    }
  }

  Set<String> get _chosen => {for (final item in _items) itemIdOf(item.type, item.id)};

  Future<void> _add() async {
    if (_items.length >= _kind.maxItems) {
      showVxSnack(
        context,
        _kind == ListKind.top ? 'Un top 10 a 10 titres au plus.' : 'Une liste a 100 titres au plus.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    final title = await pickTitle(context, chosen: _chosen);
    if (title == null || !mounted || _chosen.contains(itemIdOf(title.type, title.id))) return;
    setState(() => _items.add(title));
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _items.length) return;
    setState(() => _items.insert(target, _items.removeAt(index)));
  }

  void _setKind(ListKind kind) {
    if (kind == _kind) return;
    if (kind == ListKind.top && _items.length > kind.maxItems) {
      showVxSnack(context, 'Un top 10 a 10 titres au plus : retirez-en d’abord.', icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _kind = kind);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showVxSnack(context, 'Donnez un titre à la liste.', icon: Icons.info_outline_rounded);
      return;
    }
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _saving = true);
    final repository = ref.read(networkRepositoryProvider);
    final items = [for (final item in _items) itemIdOf(item.type, item.id)];
    final description = _description.text.trim();
    try {
      final saved = _editing
          ? await repository.updateList(
              widget.id!,
              title: title,
              description: description.isEmpty ? null : description,
              kind: _kind,
              items: items,
            )
          : await repository.createList(
              title: title,
              description: description.isEmpty ? null : description,
              kind: _kind,
              items: items,
            );
      ref.invalidate(myListsProvider);
      ref.invalidate(memberListsProvider);
      ref.invalidate(listProvider(saved.id));
      ref.invalidate(feedProvider);
      showVxSnackOn(messenger, _editing ? 'Liste enregistrée' : 'Liste créée', icon: Icons.check_rounded);
      if (_editing) {
        router.pop();
      } else {
        router.pushReplacement(listLocation(saved.id));
      }
    } catch (error) {
      showVxSnackOn(messenger, errorText(error, 'Impossible d’enregistrer la liste.'), icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final year = DateTime.now().year;
    final templates = <(String, ListKind)>[
      ('Mon top 10 de $year', ListKind.top),
      ('Mes films préférés', ListKind.top),
      ('Mes séries préférées', ListKind.top),
      ('À voir absolument', ListKind.list),
      ('Mes films réconfortants', ListKind.list),
      ('Pour une soirée frissons', ListKind.list),
    ];
    final pageTitle = _editing
        ? 'Modifier la liste'
        : _kind == ListKind.top
        ? 'Nouveau top 10'
        : 'Nouvelle liste';
    if (!_loaded) {
      return NetworkPage(
        title: pageTitle,
        children: [NetworkLoading(error: _error, onRetry: _load)],
      );
    }
    return NetworkPage(
      title: pageTitle,
      children: [
        if (!_editing && _title.text.isEmpty) ...[
          Text('Idées', style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
          SizedBox(height: layout.space(VxSpace.xs)),
          Wrap(
            spacing: layout.space(VxSpace.xs),
            runSpacing: layout.space(VxSpace.xs),
            children: [
              for (final (label, kind) in templates)
                VxButton(
                  label: label,
                  kind: VxButtonKind.outline,
                  dense: true,
                  onPressed: () => setState(() {
                    _title.text = label;
                    if (_items.length <= kind.maxItems) _kind = kind;
                  }),
                ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
        ],
        TextField(
          controller: _title,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          style: VxText.body(layout.bodySize),
          decoration: const InputDecoration(labelText: 'Titre', counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          style: VxText.body(layout.bodySize),
          decoration: const InputDecoration(
            labelText: 'Description (facultative)',
            counterText: '',
            alignLabelWithHint: true,
          ),
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        Wrap(
          spacing: layout.space(VxSpace.xs),
          children: [
            VxButton(
              label: 'Top 10',
              icon: Icons.format_list_numbered_rounded,
              kind: _kind == ListKind.top ? VxButtonKind.primary : VxButtonKind.outline,
              dense: true,
              onPressed: () => _setKind(ListKind.top),
            ),
            VxButton(
              label: 'Liste',
              icon: Icons.playlist_play_rounded,
              kind: _kind == ListKind.list ? VxButtonKind.primary : VxButtonKind.outline,
              dense: true,
              onPressed: () => _setKind(ListKind.list),
            ),
          ],
        ),
        SizedBox(height: layout.space(VxSpace.xs)),
        Text(
          _kind == ListKind.top
              ? 'Un top 10 est numéroté : le premier titre est votre numéro 1.'
              : 'Une liste garde l’ordre choisi, 100 titres au plus.',
          style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
        ),
        SizedBox(height: layout.sectionGap),
        SectionHeader(
          '${_items.length} ${_items.length > 1 ? 'titres' : 'titre'}',
          padding: EdgeInsets.only(bottom: layout.titleGap),
        ),
        for (final (i, item) in _items.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: layout.space(VxSpace.xs)),
            child: _EditorRow(
              item: item,
              rank: _kind == ListKind.top ? i + 1 : null,
              onUp: i == 0 ? null : () => _move(i, -1),
              onDown: i == _items.length - 1 ? null : () => _move(i, 1),
              onRemove: () => setState(() => _items.removeAt(i)),
            ),
          ),
        SizedBox(height: layout.space(VxSpace.xs)),
        Align(
          alignment: Alignment.centerLeft,
          child: VxButton(
            label: 'Ajouter un titre',
            icon: Icons.add_rounded,
            kind: VxButtonKind.secondary,
            dense: true,
            onPressed: _add,
          ),
        ),
        SizedBox(height: layout.sectionGap),
        VxButton(
          label: _editing ? 'Enregistrer' : 'Créer la liste',
          icon: Icons.check_rounded,
          expand: true,
          loading: _saving,
          onPressed: _title.text.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.item, required this.onRemove, this.rank, this.onUp, this.onDown});

  final MediaItem item;
  final int? rank;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Container(
      padding: EdgeInsets.all(layout.space(VxSpace.xs)),
      decoration: BoxDecoration(
        color: VxColors.surface,
        borderRadius: BorderRadius.circular(layout.size(VxRadius.button, tv: VxRadius.buttonTv)),
      ),
      child: Row(
        children: [
          if (rank != null)
            SizedBox(
              width: layout.size(28, tv: 44),
              child: Text('$rank', textAlign: TextAlign.center, style: VxText.title(layout.size(18, tv: 28))),
            ),
          PosterThumb(url: item.posterUrl, width: layout.size(36, tv: 56), seed: item.id),
          SizedBox(width: layout.space(VxSpace.s)),
          Expanded(
            child: Text(
              item.year == null ? item.title : '${item.title} (${item.year})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(layout.bodySize, weight: FontWeight.w600),
            ),
          ),
          VxIconAction(icon: Icons.arrow_upward_rounded, label: 'Monter ${item.title}', dense: true, onPressed: onUp),
          SizedBox(width: layout.space(VxSpace.xxs)),
          VxIconAction(
            icon: Icons.arrow_downward_rounded,
            label: 'Descendre ${item.title}',
            dense: true,
            onPressed: onDown,
          ),
          SizedBox(width: layout.space(VxSpace.xxs)),
          VxIconAction(icon: Icons.close_rounded, label: 'Retirer ${item.title}', dense: true, onPressed: onRemove),
        ],
      ),
    );
  }
}

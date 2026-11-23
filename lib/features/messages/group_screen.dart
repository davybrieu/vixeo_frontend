import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/session.dart';
import '../social/profile_view.dart' show AccountTile;
import 'messages.dart';
import 'widgets.dart';

/// « Nouveau groupe » (`/messages/nouveau-groupe`): its name and its members, found by their
/// @username; the profile creating it runs it. Then its conversation opens (in place of this page).
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _name = TextEditingController();
  final _members = <ChatMember>[];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => _name.text.trim().length >= 2 && _members.isNotEmpty;

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(messagesRepositoryProvider)
          .createGroup(_name.text.trim(), [for (final member in _members) member.username]);
      if (!mounted) return;
      ref.invalidate(inboxProvider);
      context.pushReplacement(conversationLocation(id));
    } catch (error) {
      if (mounted) {
        final message = errorText(error, 'Le groupe n’a pas pu être créé.');
        showVxSnack(context, message, icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return InfoPage(
      title: 'Nouveau groupe',
      fallback: '/messages',
      children: [
        InfoSection(
          title: 'Nom du groupe',
          children: [
            TextField(
              controller: _name,
              // The keyboard of a phone opens at once; a TV opens it when the field is chosen.
              autofocus: layout.isPhone,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              style: VxText.body(layout.size(16, tv: 24)),
              decoration: const InputDecoration(hintText: 'Soirée cinéma', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        InfoSection(
          title: 'Membres',
          children: [
            if (_members.isEmpty)
              Text('Ajoutez au moins un membre.', style: VxText.body(layout.bodySize, color: VxColors.textSecondary))
            else
              Wrap(
                spacing: layout.space(VxSpace.xs),
                runSpacing: layout.space(VxSpace.xs),
                children: [
                  for (final member in _members)
                    _ChosenMember(member: member, onRemove: () => setState(() => _members.remove(member))),
                ],
              ),
            SizedBox(height: layout.space(VxSpace.m)),
            MemberSearch(
              exclude: {for (final member in _members) member.id},
              pickIcon: Icons.person_add_alt_rounded,
              pickLabel: 'Ajouter',
              onPick: (member) => setState(() => _members.add(member)),
            ),
          ],
        ),
        VxButton(
          label: 'Créer le groupe',
          icon: Icons.group_add_outlined,
          expand: true,
          loading: _saving,
          onPressed: _ready && !_saving ? _create : null,
        ),
      ],
    );
  }
}

/// « Gérer le groupe » (`/messages/:id/groupe`): its name and its members; its admins rename it, add
/// and remove members and hand it over; anyone leaves it.
class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  final _name = TextEditingController();
  String _savedName = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The name, once known (and again after a rename by another admin, unless being typed).
    ref.listenManual(conversationProvider(widget.id), (_, next) {
      final name = next.value?.page.name ?? '';
      if (name != _savedName && (_name.text.trim().isEmpty || _name.text.trim() == _savedName)) _name.text = name;
      _savedName = name;
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ConversationController get _controller => ref.read(conversationProvider(widget.id).notifier);

  /// Runs a change of the group, with its alert.
  Future<void> _change(Future<void> Function(MessagesRepository repository) action, String done) async {
    setState(() => _busy = true);
    try {
      await _controller.change(action);
      if (mounted) showVxSnack(context, done);
    } catch (error) {
      if (mounted) {
        final message = errorText(error, 'Le groupe n’a pas pu être modifié.');
        showVxSnack(context, message, icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transfer(ChatMember member) async {
    final ok = await showVxConfirm(
      context,
      title: 'Transmettre l’administration ?',
      message: '${member.displayName} pourra gérer le groupe ; vous deviendrez membre.',
      confirm: 'Transmettre',
    );
    if (!ok) return;
    await _change(
      (repository) => repository.transferAdmin(widget.id, member.username),
      '${member.displayName} gère le groupe',
    );
  }

  Future<void> _remove(ChatMember member) async {
    final ok = await showVxConfirm(
      context,
      title: 'Retirer ${member.displayName} du groupe ?',
      confirm: 'Retirer',
      danger: true,
    );
    if (!ok) return;
    await _change(
      (repository) => repository.removeMember(widget.id, member.username),
      '${member.displayName} a été retiré du groupe',
    );
  }

  Future<void> _leave() async {
    final ok = await showVxConfirm(
      context,
      title: 'Quitter le groupe ?',
      message: 'Vous ne verrez plus ses messages.',
      confirm: 'Quitter',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(messagesRepositoryProvider).leave(widget.id);
      if (!mounted) return;
      ref.invalidate(inboxProvider);
      showVxSnack(context, 'Vous avez quitté le groupe');
      context.go('/messages');
    } catch (error) {
      if (mounted) {
        showVxSnack(context, errorText(error, 'Impossible de quitter le groupe.'), icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final state = ref.watch(conversationProvider(widget.id));
    final profile = ref.watch(sessionProvider.select((s) => s.profile));

    final List<Widget> children = switch (state) {
      AsyncValue(value: final data?) => () {
        final page = data.page;
        final me = ChatMember(
          id: profile?.id ?? 0,
          username: profile?.username ?? '',
          name: profile?.name ?? '',
          avatar: profile?.avatar,
          photoUrl: profile?.photoUrl,
          isAdmin: page.isAdmin,
        );
        final renamed = _name.text.trim();
        return <Widget>[
          if (page.isAdmin)
            InfoSection(
              title: 'Nom du groupe',
              children: [
                TextField(
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  style: VxText.body(layout.size(16, tv: 24)),
                  decoration: const InputDecoration(counterText: ''),
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: layout.space(VxSpace.s)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: VxButton(
                    label: 'Enregistrer le nom',
                    kind: VxButtonKind.secondary,
                    dense: true,
                    onPressed: _busy || renamed.length < 2 || renamed == page.name
                        ? null
                        : () => _change(
                            (repository) => repository.rename(widget.id, renamed),
                            'Nom du groupe enregistré',
                          ),
                  ),
                ),
              ],
            ),
          InfoSection(
            title: '${page.participants.length + 1} membres',
            children: [
              MemberRow(member: me, subtitle: page.isAdmin ? 'Vous · Administrateur' : 'Vous'),
              for (final (i, member) in page.participants.indexed) ...[
                SizedBox(height: layout.space(VxSpace.xxs)),
                Row(
                  children: [
                    Expanded(
                      child: MemberRow(
                        member: member,
                        autofocus: i == 0,
                        subtitle: member.isAdmin ? '@${member.username} · Administrateur' : null,
                        onPressed: () => context.push(AccountTile.location(member.username)),
                      ),
                    ),
                    if (page.isAdmin) ...[
                      if (!member.isAdmin) ...[
                        SizedBox(width: layout.space(VxSpace.xs)),
                        VxIconAction(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Transmettre l’administration à ${member.displayName}',
                          dense: true,
                          onPressed: _busy ? null : () => _transfer(member),
                        ),
                      ],
                      SizedBox(width: layout.space(VxSpace.xs)),
                      VxIconAction(
                        icon: Icons.person_remove_outlined,
                        label: 'Retirer ${member.displayName} du groupe',
                        dense: true,
                        onPressed: _busy ? null : () => _remove(member),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
          if (page.isAdmin)
            InfoSection(
              title: 'Ajouter des membres',
              children: [
                MemberSearch(
                  exclude: {me.id, for (final member in page.participants) member.id},
                  pickIcon: Icons.person_add_alt_rounded,
                  pickLabel: 'Ajouter',
                  onPick: (member) => _change(
                    (repository) => repository.addMembers(widget.id, [member.username]),
                    '${member.displayName} a été ajouté au groupe',
                  ),
                ),
              ],
            ),
          VxButton(
            label: 'Quitter le groupe',
            icon: Icons.logout_rounded,
            kind: VxButtonKind.danger,
            expand: true,
            onPressed: _busy ? null : _leave,
          ),
        ];
      }(),
      AsyncValue(:final error?) => [
        ErrorPanel(error: error, onRetry: () => ref.invalidate(conversationProvider(widget.id))),
      ],
      _ => [
        Padding(
          padding: EdgeInsets.only(top: layout.space(VxSpace.xxl)),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ],
    };

    return InfoPage(title: 'Gérer le groupe', fallback: conversationLocation(widget.id), children: children);
  }
}

/// A search field and the members it finds: a press on one calls [onPick] (the field empties).
class MemberSearch extends StatefulWidget {
  const MemberSearch({
    super.key,
    required this.onPick,
    this.exclude = const {},
    this.pickIcon,
    this.pickLabel = 'Écrire à',
  });

  final ValueChanged<ChatMember> onPick;
  final Set<int> exclude;
  final IconData? pickIcon;
  final String pickLabel;

  @override
  State<MemberSearch> createState() => _MemberSearchState();
}

class _MemberSearchState extends State<MemberSearch> {
  final _search = TextEditingController();
  Timer? _typing;
  String _query = '';

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  void _clear() {
    _typing?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VxSearchField(
          controller: _search,
          fontSize: layout.size(16, tv: 24),
          hintText: 'Rechercher un membre…',
          onChanged: _onChanged,
          onClear: _clear,
        ),
        if (_query.length >= 2) ...[
          SizedBox(height: layout.space(VxSpace.s)),
          MemberSearchResults(
            query: _query,
            exclude: widget.exclude,
            pickIcon: widget.pickIcon,
            pickLabel: widget.pickLabel,
            onPick: (member) {
              _clear();
              widget.onPick(member);
            },
          ),
        ],
      ],
    );
  }
}

/// A member chosen for a new group: avatar, name, ✕ (a press removes it).
class _ChosenMember extends StatelessWidget {
  const _ChosenMember({required this.member, required this.onRemove});

  final ChatMember member;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final height = layout.size(36, tv: 60);
    return VxFocusable(
      borderRadius: height / 2,
      semanticLabel: 'Retirer ${member.displayName}',
      onPressed: onRemove,
      child: Container(
        height: height,
        padding: EdgeInsets.only(left: height * 0.12, right: height * 0.3),
        decoration: BoxDecoration(
          color: VxColors.surfaceHigh,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatAvatar(member: member, size: height * 0.76),
            SizedBox(width: layout.space(VxSpace.xs)),
            Text(member.displayName, style: VxText.body(layout.size(14, tv: 24), weight: FontWeight.w500)),
            SizedBox(width: layout.space(VxSpace.xxs)),
            Icon(Icons.close_rounded, size: height * 0.5, color: VxColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

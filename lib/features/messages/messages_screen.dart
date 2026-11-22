import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/session.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key, this.conversationId, this.username});

  final int? conversationId;
  final String? username;

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _composer = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int? _conversationId;
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _participant;
  String? _conversationName;
  bool _isGroup = false;
  bool _isGroupAdmin = false;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _requests = [];

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (widget.username != null && widget.username!.isNotEmpty) {
      _startConversation(widget.username!);
    } else if (_conversationId != null) {
      _loadMessages();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages(silent: true));
    } else {
      _loadConversations();
    }
    _search.addListener(_searchUsers);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final json = await _api.get('/messages');
      final requestsJson = await _api.get('/messages/requests');
      if (!mounted) return;
      setState(() {
        _requests = (requestsJson['data'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        _conversations = (json['data'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _startConversation(String username) async {
    setState(() { _loading = true; _error = null; });
    try {
      final json = await _api.post('/messages/with/${Uri.encodeComponent(username)}');
      final id = json['conversation_id'] as int;
      if (!mounted) return;
      context.go('/messages/$id');
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final id = _conversationId;
    if (id == null) return;
    try {
      final json = await _api.get('/messages/$id');
      if (!mounted) return;
      final data = (json['data'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
      setState(() {
        _participant = json['participant'] as Map<String, dynamic>?;
        _conversationName = (json['conversation'] as Map<String, dynamic>?)?['name'] as String?;
        _isGroup = (json['conversation'] as Map<String, dynamic>?)?['type'] == 'group';
        _isGroupAdmin = json['is_admin'] == true;
        _participants = (json['participants'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        _messages = data;
        _loading = false;
        _error = null;
      });
      await _api.post('/messages/$id/read');
      if (!silent && _scroll.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (error) {
      if (!mounted || silent) return;
      setState(() { _loading = false; _error = error.toString(); });
    }
  }


  Future<void> _attach() async {
    final id = _conversationId;
    if (id == null || _sending) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.media);
      if (file == null) return;
      final length = file.lengthSync() ?? await file.length();
      if (length == null || length <= 0 || length > 100 * 1024 * 1024) {
        throw Exception('Le fichier doit faire moins de 100 Mo.');
      }
      setState(() => _sending = true);
      await _api.upload(
        '/messages/$id/attachments',
        stream: file.readAsByteStream,
        length: length,
        filename: file.name,
      );
      await _loadMessages();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _attachment(Map<String, dynamic> attachment) {
    final mime = attachment['mime_type']?.toString() ?? '';
    final url = attachment['url']?.toString() ?? '';
    if (mime.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder(
            future: _api.getBytes(url),
            builder: (context, snapshot) => snapshot.hasData
                ? Image.memory(snapshot.data!, width: 220, fit: BoxFit.cover)
                : Container(
                    width: 220, height: 120, color: VxColors.surfaceHigh,
                    alignment: Alignment.center,
                    child: snapshot.hasError ? const Icon(Icons.broken_image_outlined) : const CircularProgressIndicator(),
                  ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: VxColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_circle_outline_rounded),
          const SizedBox(width: 8),
          Flexible(child: Text(attachment['name']?.toString() ?? 'Vidéo', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    final id = _conversationId;
    if (body.isEmpty || id == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.post('/messages/$id', body: {'body': body});
      _composer.clear();
      await _loadMessages();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  Future<void> _createGroupDialog() async {
    final name = TextEditingController();
    final members = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Créer un groupe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom du groupe')),
            const SizedBox(height: 12),
            TextField(
              controller: members,
              decoration: const InputDecoration(labelText: 'Pseudos des membres', hintText: 'pseudo1, pseudo2'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
        ],
      ),
    );
    if (result == true) {
      final usernames = members.text.split(',').map((value) => value.trim().replaceFirst(RegExp(r'^@'), '')).where((value) => value.isNotEmpty).toSet().toList();
      try {
        final json = await _api.post('/messages/groups', body: {'name': name.text.trim(), 'usernames': usernames});
        if (!mounted) return;
        context.go('/messages/${json['conversation_id']}');
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
    name.dispose();
    members.dispose();
  }

  Future<void> _acceptRequest(int id) async {
    try {
      await _api.post('/messages/$id/accept');
      if (!mounted) return;
      context.go('/messages/$id');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }


  Future<void> _declineRequest(int id) async {
    try {
      await _api.delete('/messages/$id/request');
      await _loadConversations();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteMessage(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce message ?'),
        content: const Text('Le message sera supprimé pour tous les participants.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true || _conversationId == null) return;
    try {
      await _api.delete('/messages/$_conversationId/$id');
      await _loadMessages();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }


  Future<void> _manageGroup() async {
    final id = _conversationId;
    if (id == null || !_isGroup) return;
    final name = TextEditingController(text: _conversationName ?? '');
    final usernames = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gestion du groupe'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isGroupAdmin) TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom du groupe')),
                if (_isGroupAdmin) TextButton(
                  onPressed: () async {
                    try {
                      await _api.put('/messages/' + id.toString() + '/group', body: {'name': name.text.trim()});
                      if (mounted) setState(() => _conversationName = name.text.trim());
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    }
                  },
                  child: const Text('Enregistrer le nom'),
                ),
                const Text('Membres', style: TextStyle(fontWeight: FontWeight.w600)),
                ..._participants.map((member) {
                  final username = member['username']?.toString() ?? '';
                  final isAdmin = member['role'] == 'admin';
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(member['name']?.toString() ?? username),
                    subtitle: Text('@' + username + (isAdmin ? ' · Administrateur' : '')),
                    trailing: _isGroupAdmin ? PopupMenuButton<String>(
                      onSelected: (action) async {
                        try {
                          final encoded = Uri.encodeComponent(username);
                          if (action == 'transfer') {
                            await _api.post('/messages/' + id.toString() + '/group/admin/' + encoded);
                          } else if (action == 'remove') {
                            await _api.delete('/messages/' + id.toString() + '/group/members/' + encoded);
                          }
                          await _loadMessages(silent: true);
                        } catch (error) {
                          if (mounted) setState(() => _error = error.toString());
                        }
                      },
                      itemBuilder: (_) => [
                        if (!isAdmin) const PopupMenuItem(value: 'transfer', child: Text('Nommer administrateur')),
                        const PopupMenuItem(value: 'remove', child: Text('Retirer du groupe')),
                      ],
                    ) : null,
                  );
                }),
                if (_isGroupAdmin) TextField(controller: usernames, decoration: const InputDecoration(labelText: 'Ajouter des membres', hintText: 'pseudo1, pseudo2')),
                if (_isGroupAdmin) TextButton(
                  onPressed: () async {
                    final values = usernames.text.split(',').map((v) => v.trim().replaceFirst(RegExp(r'^@'), '')).where((v) => v.isNotEmpty).toSet().toList();
                    if (values.isEmpty) return;
                    try {
                      await _api.post('/messages/' + id.toString() + '/group/members', body: {'usernames': values});
                      usernames.clear();
                      await _loadMessages(silent: true);
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    }
                  },
                  child: const Text('Ajouter'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await _api.post('/messages/' + id.toString() + '/group/leave');
                if (mounted) context.go('/messages');
              } catch (error) {
                if (mounted) setState(() => _error = error.toString());
              }
            },
            child: const Text('Quitter le groupe'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
        ],
      ),
    );
    name.dispose();
    usernames.dispose();
  }

  Future<void> _blockParticipant() async {
    final username = _participant?['username']?.toString();
    if (username == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bloquer ce membre ?'),
        content: const Text('Cette personne ne pourra plus démarrer de conversation avec vous.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.post('/messages/block/${Uri.encodeComponent(username)}');
      if (mounted) context.go('/messages');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _searchUsers() async {
    final query = _search.text.trim();
    if (query.length < 2) {
      if (mounted && _suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    try {
      final json = await _api.get('/social/search', query: {'query': query});
      if (!mounted || _search.text.trim() != query) return;
      setState(() => _suggestions = (json['data'] as List? ?? []).whereType<Map<String, dynamic>>().toList());
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    }
  }

  String _time(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(sessionProvider).profile;
    if (profile?.isKid == true) {
      return const EmptyState(icon: Icons.lock_outline_rounded, title: 'Messagerie indisponible', message: 'La messagerie est réservée aux profils adultes.');
    }
    return Scaffold(
      backgroundColor: VxColors.background,
      appBar: AppBar(
        title: Text(_conversationId == null ? 'Messages' : (_conversationName ?? _participant?['name']?.toString() ?? 'Conversation')),
        actions: [
          if (_conversationId == null) IconButton(tooltip: 'Créer un groupe', onPressed: _createGroupDialog, icon: const Icon(Icons.group_add_outlined)),
          if (_conversationId != null && (_isGroup || _participant?['username'] != null)) PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') _blockParticipant();
              if (value == 'group') _manageGroup();
            },
            itemBuilder: (_) => [
              if (_isGroup) const PopupMenuItem(value: 'group', child: Text('Gérer le groupe')),
              if (!_isGroup) const PopupMenuItem(value: 'block', child: Text('Bloquer ce membre')),
            ],
          ),
        ],
        leading: _conversationId == null ? null : IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/messages'),
        ),
      ),
      body: _conversationId == null ? _buildInbox() : _buildConversation(),
    );
  }

  Widget _buildInbox() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Rechercher un membre par son pseudo',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          ..._suggestions.map((user) => ListTile(
            leading: _avatar(user['name']?.toString() ?? ''),
            title: Text(user['name']?.toString() ?? ''),
            subtitle: Text('@${user['username'] ?? ''}'),
            onTap: () => _startConversation(user['username'].toString()),
          )),
        if (_requests.isNotEmpty)
          ..._requests.map((request) {
            final sender = request['sender'] as Map<String, dynamic>? ?? {};
            return ListTile(
              leading: _avatar(sender['name']?.toString() ?? ''),
              title: Text('Demande de ${sender['name'] ?? 'membre'}'),
              subtitle: Text(request['preview']?.toString() ?? 'Souhaite vous envoyer un message'),
              trailing: Wrap(children: [
                TextButton(onPressed: () => _declineRequest(request['conversation_id'] as int), child: const Text('Refuser')),
                TextButton(onPressed: () => _acceptRequest(request['conversation_id'] as int), child: const Text('Accepter')),
              ]),
            );
          }),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyState(icon: Icons.error_outline_rounded, title: 'Impossible de charger les messages', message: _error!, action: VxButton(label: 'Réessayer', onPressed: _loadConversations))
                  : _conversations.isEmpty
                      ? const EmptyState(icon: Icons.forum_outlined, title: 'Aucun message', message: 'Recherchez un membre pour démarrer une conversation privée.')
                      : RefreshIndicator(
                          onRefresh: _loadConversations,
                          child: ListView.separated(
                            itemCount: _conversations.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                            itemBuilder: (context, index) {
                              final conversation = _conversations[index];
                              final user = conversation['participant'] as Map<String, dynamic>? ?? {};
                              final last = conversation['last_message'] as Map<String, dynamic>? ?? {};
                              final unread = conversation['unread_count'] as int? ?? 0;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: _avatar(conversation['type'] == 'group' ? (conversation['name']?.toString() ?? 'G') : (user['name']?.toString() ?? '')),
                                title: Text(conversation['type'] == 'group' ? (conversation['name']?.toString() ?? 'Groupe') : (user['name']?.toString() ?? 'Membre'), style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(last['body']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_time(conversation['updated_at']), style: const TextStyle(fontSize: 11, color: VxColors.textSecondary)),
                                    if (unread > 0) ...[
                                      const SizedBox(height: 5),
                                      CircleAvatar(radius: 10, backgroundColor: VxColors.accent, child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10))),
                                    ],
                                  ],
                                ),
                                onTap: () => context.go('/messages/${conversation['id']}'),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildConversation() {
    final profileId = ref.watch(sessionProvider).profile?.id;
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final mine = message['sender_profile_id'] == profileId;
                        final readBy = (message['read_by'] as List? ?? []).length;
                        return GestureDetector(
                          onLongPress: mine && message['deleted'] != true ? () => _deleteMessage(message['id'] as int) : null,
                          child: Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: mine ? VxColors.accent : VxColors.surface,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(mine ? 18 : 4), bottomRight: Radius.circular(mine ? 4 : 18),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if ((message['body']?.toString() ?? '').isNotEmpty) Text(message['body']?.toString() ?? '', style: TextStyle(color: mine ? Colors.white : VxColors.text)),
                                ...((message['attachments'] as List? ?? []).whereType<Map<String, dynamic>>().map(_attachment)),
                                const SizedBox(height: 4),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(_time(message['created_at']), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : VxColors.textSecondary)),
                                  if (mine && readBy > 0) ...[const SizedBox(width: 4), Icon(Icons.done_all_rounded, size: 13, color: Colors.white70)],
                                ]),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(onPressed: _sending ? null : _attach, tooltip: 'Joindre une photo ou vidéo', icon: const Icon(Icons.attach_file_rounded)),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Écrire un message…',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatar(String name) => CircleAvatar(
    backgroundColor: VxColors.accent.withValues(alpha: .15),
    child: Text(name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase(), style: const TextStyle(color: VxColors.accent, fontWeight: FontWeight.bold)),
  );
}

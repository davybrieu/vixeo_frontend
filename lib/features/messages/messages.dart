import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../notifications/inbox.dart' show socialAvailable;

// The messaging (vixeo_backend/docs/messagerie.md): conversations between adult profiles, requests
// to accept, groups run by their admins, photos and videos, read receipts. Models written from the
// API's answers, the repository (the only place that calls /messages) and the providers of the pages.

/// A member of a conversation, or the sender of a request.
class ChatMember {
  const ChatMember({required this.id, required this.username, required this.name, this.avatar, this.isAdmin = false});

  factory ChatMember.fromJson(Map<String, dynamic> json) => ChatMember(
    id: json['id'] as int? ?? 0,
    username: json['username'] as String? ?? '',
    name: json['name'] as String? ?? '',
    avatar: json['avatar'] as String?,
    isAdmin: json['role'] == 'admin',
  );

  static ChatMember? maybe(Object? json) => json is Map<String, dynamic> ? ChatMember.fromJson(json) : null;

  static List<ChatMember> listOf(Object? json) => [
    for (final item in json is List ? json : const []) ?ChatMember.maybe(item),
  ];

  final int id;
  final String username;
  final String name;
  final String? avatar;

  /// Runs the group (`role: admin`).
  final bool isAdmin;

  /// Its name, or « @pseudo » without one.
  String get displayName => name.trim().isEmpty ? '@$username' : name;
}

/// A photo or a video of a message, downloaded with the token ([attachmentBytesProvider]).
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.url,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    mimeType: json['mime_type'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    url: json['url'] as String? ?? '',
  );

  final int id;
  final String name;
  final String mimeType;

  /// In bytes.
  final int size;

  /// Under /api/v1 (`/messages/attachments/12`).
  final String url;

  bool get isImage => mimeType.startsWith('image/');
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.body,
    this.deleted = false,
    this.readBy = const [],
    this.createdAt,
    this.attachments = const [],
    this.shared,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int? ?? 0,
    senderId: json['sender_profile_id'] as int? ?? 0,
    body: json['body'] as String? ?? '',
    deleted: json['deleted'] as bool? ?? false,
    readBy: [for (final id in json['read_by'] as List? ?? const []) if (id is int) id],
    createdAt: parseDate(json['created_at']),
    attachments: [
      for (final item in json['attachments'] as List? ?? const [])
        if (item is Map<String, dynamic>) ChatAttachment.fromJson(item),
    ],
    shared: json['shared'] is Map<String, dynamic> ? SharedCard.fromJson(json['shared'] as Map<String, dynamic>) : null,
  );

  static List<ChatMessage> listOf(Object? json) => [
    for (final item in json is List ? json : const [])
      if (item is Map<String, dynamic>) ChatMessage.fromJson(item),
  ];

  final int id;
  final int senderId;

  /// The text (empty for an attachment alone; « Ce message a été supprimé. » once deleted).
  final String body;
  final bool deleted;

  /// Profiles that read it.
  final List<int> readBy;

  /// Local time.
  final DateTime? createdAt;
  final List<ChatAttachment> attachments;

  /// A title, a review or a list sent with the message (« Envoyer à un ami »).
  final SharedCard? shared;
}

/// A title, a review or a list in a message (`shared`, vixeo_backend/docs/messagerie.md): what it
/// was when it was sent (picture, title, a line), and the page a press opens.
class SharedCard {
  const SharedCard({
    required this.kind,
    required this.title,
    required this.path,
    this.subtitle,
    this.excerpt,
    this.images = const [],
  });

  factory SharedCard.fromJson(Map<String, dynamic> json) {
    final author = json['author'] is Map<String, dynamic> ? json['author'] as Map<String, dynamic> : null;
    final by = author == null ? null : (author['username'] as String? ?? '');
    switch (json['type']) {
      case 'review':
        final value = (json['value'] as num?)?.toDouble();
        final season = json['season_number'] as int?;
        final episode = json['episode_number'] as int?;
        return SharedCard(
          kind: 'review',
          title: '${json['title'] as String? ?? ''}${episode == null ? '' : ' · S$season · É$episode'}',
          path: '/avis/${json['review_id']}',
          subtitle: [
            if (by != null && by.isNotEmpty) 'Avis de @$by',
            if (value != null) '★ ${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1).replaceAll('.', ',')}/10',
          ].join(' · '),
          excerpt: json['excerpt'] as String?,
          images: [if (json['poster_url'] case final String url) url],
        );
      case 'list':
        final count = json['items_count'] as int? ?? 0;
        return SharedCard(
          kind: 'list',
          title: json['title'] as String? ?? '',
          path: '/listes/${json['list_id']}',
          subtitle: [
            'Liste',
            '$count ${count > 1 ? 'titres' : 'titre'}',
            if (by != null && by.isNotEmpty) '@$by',
          ].join(' · '),
          images: [for (final url in json['cover'] as List? ?? const []) if (url is String) url],
        );
      default:
        final type = json['media_type'] == 'tv' ? 'tv' : 'movie';
        final year = json['year'] as int?;
        return SharedCard(
          kind: 'title',
          title: json['title'] as String? ?? '',
          path: '/titre/$type/${json['id']}',
          subtitle: [type == 'tv' ? 'Série' : 'Film', if (year != null) '$year'].join(' · '),
          images: [if (json['poster_url'] case final String url) url],
        );
    }
  }

  /// `title`, `review` or `list`.
  final String kind;
  final String title;

  /// The page it opens (`/titre/movie/550`, `/avis/12`, `/listes/3`).
  final String path;
  final String? subtitle;

  /// The beginning of a review's comment (none with spoilers).
  final String? excerpt;

  /// Its poster, or the first posters of a list.
  final List<String> images;
}

/// A date of the API (ISO 8601 with its time zone), in local time.
DateTime? parseDate(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// A conversation in « Messages ».
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    this.isGroup = false,
    this.name,
    this.participants = const [],
    this.lastMessage,
    this.lastSenderId,
    this.unreadCount = 0,
    this.isPending = false,
    this.updatedAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    return ConversationSummary(
      id: json['id'] as int? ?? 0,
      isGroup: json['type'] == 'group',
      name: json['name'] as String?,
      participants: ChatMember.listOf(json['participants']),
      lastMessage: last is Map<String, dynamic> ? last['body'] as String? : null,
      lastSenderId: last is Map<String, dynamic> ? last['sender_profile_id'] as int? : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      isPending: json['status'] == 'pending',
      updatedAt: parseDate(json['updated_at']),
    );
  }

  final int id;
  final bool isGroup;

  /// A group's name.
  final String? name;

  /// The members besides the active profile.
  final List<ChatMember> participants;
  final String? lastMessage;
  final int? lastSenderId;
  final int unreadCount;

  /// A request the active profile made, waiting for an answer.
  final bool isPending;
  final DateTime? updatedAt;

  /// The other profile of a direct conversation.
  ChatMember? get participant => isGroup ? null : participants.firstOrNull;

  String get title => isGroup ? (name ?? 'Groupe') : (participant?.displayName ?? 'Membre');
}

/// A request the active profile received: who sent it and its first message.
class MessageRequest {
  const MessageRequest({required this.conversationId, this.sender, this.preview});

  factory MessageRequest.fromJson(Map<String, dynamic> json) => MessageRequest(
    conversationId: json['conversation_id'] as int? ?? 0,
    sender: ChatMember.maybe(json['sender']),
    preview: json['preview'] as String?,
  );

  final int conversationId;
  final ChatMember? sender;
  final String? preview;
}

/// « Messages »: the requests received, then the conversations.
class Inbox {
  const Inbox({this.conversations = const [], this.requests = const [], this.unreadCount = 0});

  final List<ConversationSummary> conversations;
  final List<MessageRequest> requests;

  /// Unread messages of the conversations.
  final int unreadCount;
}

/// A page of a conversation (GET /messages/{id}).
class ConversationPage {
  const ConversationPage({
    required this.id,
    this.isGroup = false,
    this.name,
    this.isPending = false,
    this.isRequest = false,
    this.participants = const [],
    this.isAdmin = false,
    this.blocked = false,
    this.messages = const [],
    this.hasMore = false,
  });

  factory ConversationPage.fromJson(Map<String, dynamic> json) {
    final conversation = json['conversation'] as Map<String, dynamic>? ?? const {};
    return ConversationPage(
      id: conversation['id'] as int? ?? 0,
      isGroup: conversation['type'] == 'group',
      name: conversation['name'] as String?,
      isPending: conversation['status'] == 'pending',
      isRequest: conversation['is_request'] as bool? ?? false,
      participants: ChatMember.listOf(json['participants']),
      isAdmin: json['is_admin'] as bool? ?? false,
      blocked: json['blocked'] as bool? ?? false,
      messages: ChatMessage.listOf(json['data']),
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  final int id;
  final bool isGroup;
  final String? name;

  /// A request not answered yet (by either profile).
  final bool isPending;

  /// A request the active profile received: « Accepter » / « Refuser ».
  final bool isRequest;

  /// The members besides the active profile.
  final List<ChatMember> participants;

  /// The active profile runs this group.
  final bool isAdmin;

  /// The active profile blocked the other profile of this direct conversation.
  final bool blocked;

  /// Oldest first.
  final List<ChatMessage> messages;

  /// Older messages exist (`before`).
  final bool hasMore;

  ChatMember? get participant => isGroup ? null : participants.firstOrNull;

  String get title => isGroup ? (name ?? 'Groupe') : (participant?.displayName ?? 'Conversation');
}

/// The only place that calls `/messages`.
class MessagesRepository {
  MessagesRepository(this._api);

  final ApiClient _api;

  static String _user(String username) => Uri.encodeComponent(username);

  Future<({List<ConversationSummary> conversations, int unreadCount})> conversations() async {
    final json = await _api.get('/messages');
    return (
      conversations: [
        for (final item in json['data'] as List? ?? const [])
          if (item is Map<String, dynamic>) ConversationSummary.fromJson(item),
      ],
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  /// Messages of the others not read yet, in every conversation, the requests received included
  /// (the badge of « Messages »).
  Future<int> unreadCount() async => (await _api.get('/messages/count'))['unread_count'] as int? ?? 0;

  Future<List<MessageRequest>> requests() async {
    final json = await _api.get('/messages/requests');
    return [
      for (final item in json['data'] as List? ?? const [])
        if (item is Map<String, dynamic>) MessageRequest.fromJson(item),
    ];
  }

  /// The conversation with [username] (a request when there was none): its id.
  Future<int> start(String username) async =>
      (await _api.post('/messages/with/${_user(username)}'))['conversation_id'] as int;

  Future<int> createGroup(String name, List<String> usernames) async =>
      (await _api.post('/messages/groups', body: {'name': name, 'usernames': usernames}))['conversation_id'] as int;

  Future<ConversationPage> conversation(int id, {int? before}) async =>
      ConversationPage.fromJson(await _api.get('/messages/$id', query: {'before': before}));

  Future<ChatMessage> send(int id, String body) async =>
      ChatMessage.fromJson((await _api.post('/messages/$id', body: {'body': body}))['data'] as Map<String, dynamic>);

  Future<ChatMessage> attach(
    int id, {
    required Stream<List<int>> Function() stream,
    required int length,
    required String filename,
  }) async => ChatMessage.fromJson(
    (await _api.upload('/messages/$id/attachments', stream: stream, length: length, filename: filename))['data']
        as Map<String, dynamic>,
  );

  Future<Uint8List> attachment(String url) => _api.getBytes(url);

  Future<void> delete(int conversation, int message) => _api.delete('/messages/$conversation/$message');

  Future<void> markRead(int id) => _api.post('/messages/$id/read');

  Future<void> accept(int id) => _api.post('/messages/$id/accept');

  Future<void> decline(int id) => _api.delete('/messages/$id/request');

  Future<void> rename(int id, String name) => _api.put('/messages/$id/group', body: {'name': name});

  Future<void> addMembers(int id, List<String> usernames) =>
      _api.post('/messages/$id/group/members', body: {'usernames': usernames});

  Future<void> removeMember(int id, String username) => _api.delete('/messages/$id/group/members/${_user(username)}');

  Future<void> leave(int id) => _api.post('/messages/$id/group/leave');

  Future<void> transferAdmin(int id, String username) => _api.post('/messages/$id/group/admin/${_user(username)}');

  Future<void> block(String username) => _api.post('/messages/block/${_user(username)}');

  Future<void> unblock(String username) => _api.delete('/messages/block/${_user(username)}');
}

final messagesRepositoryProvider = Provider<MessagesRepository>(
  (ref) => MessagesRepository(ref.read(apiClientProvider)),
);

/// « Messages » of the active profile: the requests it received and its conversations. Read again
/// when a conversation is read, written to or answered (invalidated), and by pulling the list.
final inboxProvider = FutureProvider.autoDispose<Inbox>((ref) async {
  if (!socialAvailable(ref.watch(sessionProvider))) return const Inbox();
  final repository = ref.read(messagesRepositoryProvider);
  final list = await repository.conversations();
  final requests = await repository.requests();
  return Inbox(conversations: list.conversations, requests: requests, unreadCount: list.unreadCount);
});

/// Unread messages: the badge of « Messages » in the navigation (« 9+ » above 9). Read again when
/// the navigation is shown or changes page (30 s at most between two), when the app comes back to
/// the foreground, when a push of the `social` channel arrives (messages are pushed there) and
/// after a conversation is read or a request declined; no timer.
final unreadMessagesProvider = NotifierProvider<UnreadMessages, int>(UnreadMessages.new);

class UnreadMessages extends Notifier<int> {
  DateTime? _readAt;

  /// Shortest time between two readings, unless forced.
  static const minInterval = Duration(seconds: 30);

  @override
  int build() {
    ref.watch(sessionProvider.select((s) => (s.status, s.profile?.id)));
    _readAt = null;
    return 0;
  }

  Future<void> refresh({bool force = false}) async {
    if (!socialAvailable(ref.read(sessionProvider))) return;
    final now = DateTime.now();
    final last = _readAt;
    if (!force && last != null && now.difference(last) < minInterval) return;
    _readAt = now;
    try {
      final count = await ref.read(messagesRepositoryProvider).unreadCount();
      if (ref.mounted) state = count;
    } catch (_) {
      // Offline, server down: the badge stays as it was.
    }
  }
}

/// The bytes of an attachment (members only, with the token): kept 5 minutes after the last
/// message showing it left the screen, so scrolling back doesn't download it again.
final attachmentBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, url) {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() => release = Timer(const Duration(minutes: 5), link.close));
  ref.onResume(() => release?.cancel());
  ref.onDispose(() => release?.cancel());
  return ref.read(messagesRepositoryProvider).attachment(url);
});

/// What a conversation page shows: its members and status ([page], the latest reading) and every
/// message loaded so far, oldest first (the latest page and the older ones scrolled up to).
class ConversationState {
  const ConversationState({
    required this.page,
    required this.messages,
    this.hasMore = false,
    this.loadingOlder = false,
  });

  final ConversationPage page;
  final List<ChatMessage> messages;
  final bool hasMore;
  final bool loadingOlder;

  ConversationState copyWith({
    ConversationPage? page,
    List<ChatMessage>? messages,
    bool? hasMore,
    bool? loadingOlder,
  }) => ConversationState(
    page: page ?? this.page,
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    loadingOlder: loadingOlder ?? this.loadingOlder,
  );
}

/// The real-time channel of conversation [id] (vixeo_backend/docs/reverb.md): `message.sent`,
/// `message.deleted`, `message.read`, `message.updated`, or `resync` after a reconnection.
String conversationChannel(int id) => 'private-messages.$id';

/// A conversation: read when its page opens, read again when the API announces a change on its
/// channel ([conversationChannel]) or after an action, marked read as it is shown.
final conversationProvider = AsyncNotifierProvider.autoDispose.family<ConversationController, ConversationState, int>(
  ConversationController.new,
);

class ConversationController extends AsyncNotifier<ConversationState> {
  ConversationController(this.id);

  final int id;

  Future<void>? _refreshing;
  bool _refreshAgain = false;

  MessagesRepository get _repository => ref.read(messagesRepositoryProvider);

  @override
  Future<ConversationState> build() async {
    // Listened to before the first reading: nothing announced meanwhile is missed.
    final changes = ref.watch(realtimeProvider).events(conversationChannel(id)).listen((_) => unawaited(refresh()));
    ref.onDispose(changes.cancel);
    final page = await _repository.conversation(id);
    _markRead(page.messages);
    return ConversationState(page: page, messages: page.messages, hasMore: page.hasMore);
  }

  /// Reads the latest page again, keeping the older messages already loaded. Several changes at
  /// once make one more reading, not one each.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) {
      _refreshAgain = true;
      return running;
    }
    return _refreshing = _readLatest().whenComplete(() {
      _refreshing = null;
      if (_refreshAgain && ref.mounted) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    });
  }

  Future<void> _readLatest() async {
    try {
      final page = await _repository.conversation(id);
      if (!ref.mounted) return;
      final current = state.value;
      final firstLatest = page.messages.firstOrNull?.id;
      final older = [
        if (current != null && firstLatest != null)
          for (final message in current.messages)
            if (message.id < firstLatest) message,
      ];
      state = AsyncData(
        ConversationState(
          page: page,
          messages: [...older, ...page.messages],
          hasMore: older.isEmpty ? page.hasMore : current!.hasMore,
        ),
      );
      _markRead(page.messages);
    } catch (_) {
      // Offline for a moment: what is shown stays; the next change reads it again.
    }
  }

  /// The messages before the oldest one shown (scrolled to the top).
  Future<void> loadOlder() async {
    final current = state.value;
    final oldest = current?.messages.firstOrNull;
    if (current == null || oldest == null || !current.hasMore || current.loadingOlder) return;
    state = AsyncData(current.copyWith(loadingOlder: true));
    try {
      final page = await _repository.conversation(id, before: oldest.id);
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(messages: [...page.messages, ...latest.messages], hasMore: page.hasMore, loadingOlder: false),
      );
    } catch (_) {
      if (ref.mounted) state = AsyncData((state.value ?? current).copyWith(loadingOlder: false));
    }
  }

  Future<void> send(String body) async => _add(await _repository.send(id, body));

  Future<void> attach({
    required Stream<List<int>> Function() stream,
    required int length,
    required String filename,
  }) async => _add(await _repository.attach(id, stream: stream, length: length, filename: filename));

  Future<void> delete(int messageId) => change((repository) => repository.delete(id, messageId));

  Future<void> accept() => change((repository) => repository.accept(id));

  /// Runs a change of the conversation ([action] of the repository: accept, a group change…), then
  /// reads it again.
  Future<void> change(Future<void> Function(MessagesRepository repository) action) async {
    await action(_repository);
    if (!ref.mounted) return;
    await refresh();
    _listChanged();
  }

  void _add(ChatMessage message) {
    if (!ref.mounted) return;
    final current = state.value;
    if (current != null && !current.messages.any((m) => m.id == message.id)) {
      state = AsyncData(current.copyWith(messages: [...current.messages, message]));
    }
    // The list shows it as the last message, at the top.
    _listChanged();
  }

  /// « Messages » reads its list again (last message, unread counts), and the badge its number.
  void _listChanged() {
    if (!ref.mounted) return;
    ref.invalidate(inboxProvider);
    unawaited(ref.read(unreadMessagesProvider.notifier).refresh(force: true));
  }

  /// Marks the conversation read when it shows messages of the others not read yet.
  void _markRead(List<ChatMessage> messages) {
    final me = ref.read(sessionProvider).profile?.id;
    if (me == null || !messages.any((m) => m.senderId != me && !m.deleted && !m.readBy.contains(me))) return;
    final repository = _repository;
    unawaited(() async {
      try {
        await repository.markRead(id);
        _listChanged();
      } catch (_) {
        // Read on the next visit.
      }
    }());
  }
}

/// Opens the conversation with [username] (asked first: a request when there was none).
Future<int> startConversation(WidgetRef ref, String username) =>
    ref.read(messagesRepositoryProvider).start(username);

/// Where a conversation opens.
String conversationLocation(int id) => '/messages/$id';

/// « Gérer le groupe » of a group conversation.
String groupSettingsLocation(int id) => '/messages/$id/groupe';

/// « Créer un groupe ».
const newGroupLocation = '/messages/nouveau-groupe';

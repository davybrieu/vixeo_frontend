import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/realtime.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/messages/conversation_screen.dart';
import 'package:vixeo/features/messages/conversations_screen.dart';
import 'package:vixeo/features/messages/messages.dart';
import 'package:vixeo/features/messages/widgets.dart';
import 'package:vixeo/features/profiles/avatars.dart';

import 'realtime_fakes.dart';

// The messaging (vixeo_backend/docs/messagerie.md): its models, the real-time connection (Reverb)
// and the pages « Messages » and a conversation.

class _Session extends SessionController {
  _Session([this.profile = const Profile(id: 2, name: 'Léa', username: 'lea')]);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', profile: profile);
}

const _max = ChatMember(id: 7, username: 'max', name: 'Max');
const _nina = ChatMember(id: 9, username: 'nina', name: 'Nina');

class _FakeMessages extends MessagesRepository {
  _FakeMessages(this.page) : super(ApiClient(token: () => null));

  ConversationPage page;
  final calls = <String>[];
  int unread = 4;

  @override
  Future<int> unreadCount() async {
    calls.add('count');
    return unread;
  }

  @override
  Future<({List<ConversationSummary> conversations, int unreadCount})> conversations() async => (
    conversations: [
      ConversationSummary(
        id: 5,
        participants: const [_max],
        lastMessage: 'À ce soir',
        lastSenderId: 2,
        updatedAt: DateTime.now(),
      ),
      ConversationSummary(
        id: 6,
        isGroup: true,
        name: 'Cinéma',
        participants: const [_max, _nina],
        lastMessage: 'On y va ?',
        lastSenderId: 7,
        unreadCount: 3,
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ],
    unreadCount: 3,
  );

  @override
  Future<List<MessageRequest>> requests() async => [
    const MessageRequest(conversationId: 3, sender: _nina, preview: 'Coucou !'),
  ];

  @override
  Future<ConversationPage> conversation(int id, {int? before}) async => page;

  @override
  Future<ChatMessage> send(int id, String body) async {
    calls.add('send $body');
    return ChatMessage(id: 99, senderId: 2, body: body, createdAt: DateTime.now());
  }

  @override
  Future<void> markRead(int id) async => calls.add('read $id');

  @override
  Future<void> accept(int id) async {
    calls.add('accept $id');
    page = _page();
  }

  @override
  Future<void> decline(int id) async => calls.add('decline $id');
}

ConversationPage _page({bool request = false}) => ConversationPage(
  id: 5,
  isPending: request,
  isRequest: request,
  participants: const [_max],
  messages: [
    ChatMessage(id: 1, senderId: 7, body: 'Salut Léa', createdAt: DateTime.now().subtract(const Duration(minutes: 3))),
    if (!request)
      ChatMessage(id: 2, senderId: 2, body: 'Salut Max', readBy: const [7], createdAt: DateTime.now()),
  ],
);

Finder _pressable(String label) =>
    find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == label);

Future<_FakeMessages> _pump(WidgetTester tester, Widget home, {ConversationPage? page}) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _FakeMessages(page ?? _page());
  Widget other(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: home)),
      GoRoute(path: '/messages/:id', builder: (_, state) => other('Conversation ${state.pathParameters['id']}')),
      GoRoute(path: '/membre/:username', builder: (_, state) => other('Membre ${state.pathParameters['username']}')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        messagesRepositoryProvider.overrideWithValue(repository),
        // No Reverb key in the tests: no socket.
        realtimeProvider.overrideWithValue(Realtime(authorize: (_, _) async => null)),
        avatarCatalogProvider.overrideWith((ref) async => const <AvatarLicense>[]),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// A WebSocket that the test plays the server of.
/// The events of conversation [id], by name.
Stream<String> changesOf(Realtime realtime, int id) =>
    realtime.events(conversationChannel(id)).map((event) => event.name);

void main() {
  group('models', () {
    test('a conversation page, its members and its messages', () {
      final page = ConversationPage.fromJson({
        'conversation': {'id': 6, 'type': 'group', 'name': 'Cinéma', 'status': 'accepted', 'is_request': false},
        'participants': [
          {'id': 7, 'username': 'max', 'name': 'Max', 'avatar': null, 'role': 'admin'},
          {'id': 9, 'username': 'nina', 'name': '', 'avatar': 'robot', 'role': 'member'},
        ],
        'is_admin': false,
        'participant': null,
        'blocked': false,
        'data': [
          {
            'id': 12,
            'sender_profile_id': 7,
            'body': '',
            'deleted': false,
            'read_by': [2, 9],
            'created_at': '2026-11-22T20:00:00+00:00',
            'attachments': [
              {'id': 3, 'name': 'plage.jpg', 'mime_type': 'image/jpeg', 'size': 2048, 'url': '/messages/attachments/3'},
            ],
          },
        ],
        'has_more': true,
      });

      expect(page.isGroup, isTrue);
      expect(page.title, 'Cinéma');
      expect(page.participant, isNull);
      expect(page.participants.first.isAdmin, isTrue);
      expect(page.participants.last.displayName, '@nina');
      expect(page.hasMore, isTrue);
      final message = page.messages.single;
      expect(message.readBy, [2, 9]);
      expect(message.attachments.single.isImage, isTrue);
      // A UTC date of the API, in local time.
      expect(message.createdAt, DateTime.utc(2026, 11, 22, 20).toLocal());
    });

    test('a conversation of the list: its title and its other profile', () {
      final direct = ConversationSummary.fromJson({
        'id': 5,
        'type': 'direct',
        'name': null,
        'participants': [
          {'id': 7, 'username': 'max', 'name': 'Max', 'role': 'member'},
        ],
        'last_message': {'id': 1, 'body': 'Salut', 'sender_profile_id': 7, 'created_at': '2026-11-22T20:00:00Z'},
        'unread_count': 2,
        'status': 'pending',
        'updated_at': '2026-11-22T20:00:00Z',
      });
      expect(direct.title, 'Max');
      expect(direct.participant?.username, 'max');
      expect(direct.lastMessage, 'Salut');
      expect(direct.unreadCount, 2);
      expect(direct.isPending, isTrue);
    });

    test('dates and sizes as the pages write them', () {
      final now = DateTime(2026, 11, 23, 15);
      expect(conversationTime(DateTime(2026, 11, 23, 9, 5), now), '09:05');
      expect(conversationTime(DateTime(2026, 11, 22, 23), now), 'Hier');
      expect(conversationTime(DateTime(2026, 11, 19), now), 'jeu.');
      expect(conversationTime(DateTime(2026, 10, 2), now), '02/10');
      expect(messageDay(DateTime(2026, 11, 23, 8), now), 'Aujourd’hui');
      expect(fileSize(2048), '2 Ko');
      expect(fileSize(5 * 1024 * 1024 + 300000), '5,3 Mo');
    });
  });

  group('real time', () {
    test('one socket, a channel per conversation shown, its changes; closed with the last one', () async {
      final sockets = <FakeSocket>[];
      final authorized = <String>[];
      final realtime = Realtime(
        endpoint: Uri.parse('wss://api.vixeo.test/app/key'),
        connect: (_) async => sockets.last,
        authorize: (socketId, channel) async {
          authorized.add('$socketId $channel');
          return 'signed';
        },
      );
      addTearDown(realtime.dispose);
      sockets.add(FakeSocket());

      final changes = <String>[];
      final first = changesOf(realtime, 12).listen(changes.add);
      await pumpEventQueue();
      final socket = sockets.single;
      socket.server('pusher:connection_established', {'socket_id': '1.2', 'activity_timeout': 30});
      await pumpEventQueue();
      expect(authorized, ['1.2 private-messages.12']);
      expect(socket.sent.last, {
        'event': 'pusher:subscribe',
        'data': {'auth': 'signed', 'channel': 'private-messages.12'},
      });

      socket
        ..server('message.sent', {'conversation_id': 12}, channel: 'private-messages.12')
        ..server('message.sent', {'conversation_id': 13}, channel: 'private-messages.13')
        ..server('pusher:ping', {});
      await pumpEventQueue();
      expect(changes, ['message.sent']);
      expect(socket.sent.last['event'], 'pusher:pong');

      // Another conversation: the same socket.
      final second = changesOf(realtime, 13).listen((_) {});
      await pumpEventQueue();
      expect(authorized.last, '1.2 private-messages.13');
      await second.cancel();
      expect(socket.sent.last, {
        'event': 'pusher:unsubscribe',
        'data': {'channel': 'private-messages.13'},
      });
      expect(socket.closed, isFalse);

      await first.cancel();
      await pumpEventQueue();
      expect(socket.closed, isTrue);
    });

    test('reconnects after a drop and says what may have been missed', () async {
      final sockets = [FakeSocket()];
      final realtime = Realtime(
        endpoint: Uri.parse('wss://api.vixeo.test/app/key'),
        connect: (_) async => sockets.last,
        authorize: (_, _) async => 'signed',
      );
      addTearDown(realtime.dispose);
      final changes = <String>[];
      final subscription = changesOf(realtime, 12).listen(changes.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      sockets.last.server('pusher:connection_established', {'socket_id': '1.2'});
      await pumpEventQueue();

      sockets.add(FakeSocket());
      await sockets.first.drop();
      // The first retry comes after a second.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      sockets.last.server('pusher:connection_established', {'socket_id': '3.4'});
      await pumpEventQueue();
      expect(sockets.last.sent.last['event'], 'pusher:subscribe');
      sockets.last.server('pusher_internal:subscription_succeeded', {}, channel: 'private-messages.12');
      await pumpEventQueue();
      expect(changes, [Realtime.resync]);
    });

    test('no Reverb key in the build: nothing opens', () async {
      var connections = 0;
      final realtime = Realtime(
        connect: (_) async {
          connections++;
          return FakeSocket();
        },
        authorize: (_, _) async => 'signed',
      );
      addTearDown(realtime.dispose);
      final subscription = changesOf(realtime, 12).listen((_) {});
      await pumpEventQueue();
      await subscription.cancel();
      expect(realtime.enabled, isFalse);
      expect(connections, 0);
    });
  });

  group('badge', () {
    ProviderContainer container(_FakeMessages repository, {Profile? profile}) {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => profile == null ? _Session() : _Session(profile)),
          messagesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the unread messages, read again 30 s apart at most unless forced', () async {
      final repository = _FakeMessages(_page());
      final badge = container(repository);

      await badge.read(unreadMessagesProvider.notifier).refresh();
      expect(badge.read(unreadMessagesProvider), 4);

      repository.unread = 12;
      await badge.read(unreadMessagesProvider.notifier).refresh();
      expect(badge.read(unreadMessagesProvider), 4);
      await badge.read(unreadMessagesProvider.notifier).refresh(force: true);
      expect(badge.read(unreadMessagesProvider), 12);
      expect(repository.calls, ['count', 'count']);
    });

    test('the account profile can read its unread-message badge without child-profile gating', () async {
      final repository = _FakeMessages(_page());
      final badge = container(repository, profile: const Profile(id: 3, name: 'Tom'));

      await badge.read(unreadMessagesProvider.notifier).refresh(force: true);
      expect(badge.read(unreadMessagesProvider), 4);
      expect(repository.calls, ['count']);
    });
  });

  group('pages', () {
    testWidgets('« Messages »: the requests to answer, then the conversations', (tester) async {
      final repository = await _pump(tester, const ConversationsScreen());

      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Demandes de message'), findsOneWidget);
      expect(find.text('Coucou !'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('Vous : À ce soir'), findsOneWidget);
      expect(find.text('Cinéma'), findsOneWidget);
      expect(find.text('On y va ?'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Hier'), findsOneWidget);

      await tester.tap(_pressable('Accepter la demande de Nina'));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('accept 3'));
      expect(find.text('Conversation 3'), findsOneWidget);
    });

    testWidgets('a conversation: its messages, read as shown, and a message sent', (tester) async {
      final repository = await _pump(tester, const ConversationScreen(id: 5));

      expect(find.text('Max'), findsOneWidget);
      expect(find.text('Salut Léa'), findsOneWidget);
      expect(find.text('Salut Max'), findsOneWidget);
      // Read by Max: ✓✓.
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(repository.calls, contains('read 5'));
      // Read: the badge of « Messages » is read again.
      expect(repository.calls, contains('count'));

      await tester.enterText(find.byType(TextField), '  À ce soir  ');
      await tester.tap(_pressable('Envoyer'));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('send À ce soir'));
      expect(find.text('À ce soir'), findsOneWidget);
    });

    testWidgets('a request received is answered before writing', (tester) async {
      final repository = await _pump(tester, const ConversationScreen(id: 5), page: _page(request: true));

      expect(find.text('Max souhaite vous écrire. Acceptez pour répondre.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(_pressable('Accepter'));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('accept 5'));
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}

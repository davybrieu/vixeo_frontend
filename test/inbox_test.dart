import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/features.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/messages/messages.dart';
import 'package:vixeo/features/notifications/inbox.dart';
import 'package:vixeo/features/notifications/inbox_screen.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/shell/app_shell.dart';
import 'package:vixeo/features/social/social_links.dart';
import 'package:vixeo/features/social/social_repository.dart';
import 'package:vixeo/features/tmdb/tmdb.dart';

// The « Notifications » page and its badge in the navigation (developer's request, 21/11/2026).

class _Session extends SessionController {
  _Session([this.profile = const Profile(id: 2, name: 'Léa', username: 'lea')]);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', profile: profile);
}

final _now = DateTime.now();

class _FakeInbox extends InboxRepository {
  _FakeInbox() : super(ApiClient(token: () => null));

  int reads = 0;

  @override
  Future<ActivityPage> activity({int page = 1}) async => ActivityPage(
    currentPage: 1,
    lastPage: 1,
    items: [
      Activity(
        id: 1,
        type: ActivityType.reviewLike,
        actor: const SocialProfile(id: 7, username: 'max', name: 'Max'),
        createdAt: _now.subtract(const Duration(minutes: 5)),
        review: const RatedItem(type: RatedType.movie, id: 550, title: 'Fight Club', value: 9, reviewId: 31),
      ),
      Activity(
        id: 2,
        type: ActivityType.follow,
        actor: const SocialProfile(id: 7, username: 'max', name: 'Max'),
        createdAt: _now.subtract(const Duration(hours: 3)),
        read: true,
      ),
      // A request: in its own section.
      Activity(
        id: 3,
        type: ActivityType.followRequest,
        actor: const SocialProfile(id: 9, username: 'nina', name: 'Nina'),
        createdAt: _now.subtract(const Duration(hours: 4)),
      ),
    ],
  );

  @override
  Future<void> markRead() async => reads++;

  @override
  Future<int> unreadCount() async => 2;

  @override
  Future<EpisodeCalendar> episodes() async {
    final tomorrow = DateTime(_now.year, _now.month, _now.day + 1, 21);
    return EpisodeCalendar(
      upcoming: [
        ShowEpisode(
          showId: 1399,
          showName: 'Les Hautes Terres',
          seasonNumber: 2,
          episodeNumber: 5,
          name: 'Le Retour',
          availableAt: tomorrow,
        ),
      ],
      recent: [
        ShowEpisode(
          showId: 100088,
          showName: 'Lupin',
          seasonNumber: 4,
          episodeNumber: 1,
          availableAt: DateTime(_now.year, _now.month, _now.day - 1, 8),
        ),
      ],
    );
  }
}

class _FakeSocial extends SocialRepository {
  _FakeSocial() : super(ApiClient(token: () => null));

  final calls = <String>[];
  var waiting = [const SocialProfile(id: 9, username: 'nina', name: 'Nina')];

  @override
  Future<List<SocialProfile>> requests() async => waiting;

  @override
  Future<void> acceptRequest(String username) async {
    calls.add('accept $username');
    waiting = [];
  }

  @override
  Future<void> declineRequest(String username) async {
    calls.add('decline $username');
    waiting = [];
  }
}

Finder _pressable(String label) =>
    find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == label);

Future<({_FakeInbox inbox, _FakeSocial social, ProviderContainer container})> _pumpInbox(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final inbox = _FakeInbox();
  final social = _FakeSocial();
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(_Session.new),
      inboxRepositoryProvider.overrideWithValue(inbox),
      socialRepositoryProvider.overrideWithValue(social),
      avatarCatalogProvider.overrideWith((ref) async => const <AvatarLicense>[]),
    ],
  );
  addTearDown(container.dispose);
  Widget page(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: InboxScreen())),
      GoRoute(path: '/membre/:username', builder: (_, state) => page('Membre ${state.pathParameters['username']}')),
      GoRoute(path: '/titre/:type/:id', builder: (_, state) => page('Fiche ${state.pathParameters['id']}')),
      GoRoute(path: '/avis/:id', builder: (_, state) => page('Avis ${state.pathParameters['id']}')),
      GoRoute(
        path: '/avis/:type/:id',
        builder: (_, state) => page('Avis ${state.pathParameters['type']} ${state.pathParameters['id']}'),
      ),
      GoRoute(path: '/listes/:id', builder: (_, state) => page('Liste ${state.pathParameters['id']}')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (inbox: inbox, social: social, container: container);
}

class _Unread extends UnreadNotifications {
  @override
  int build() => 3;

  @override
  Future<void> refresh({bool force = false}) async {}
}

class _UnreadMessages extends UnreadMessages {
  @override
  int build() => 12;

  @override
  Future<void> refresh({bool force = false}) async {}
}

Widget _shell(Profile profile) => ProviderScope(
  // A new scope each time (its overrides are read once).
  key: UniqueKey(),
  overrides: [
    sessionProvider.overrideWith(() => _Session(profile)),
    liveTvProvider.overrideWithValue(false),
    unreadNotificationsProvider.overrideWith(_Unread.new),
    unreadMessagesProvider.overrideWith(_UnreadMessages.new),
    avatarCatalogProvider.overrideWith((ref) async => const <AvatarLicense>[]),
  ],
  child: MaterialApp(
    theme: buildVixeoTheme(),
    home: const AppShell(location: '/recherche', child: SizedBox()),
  ),
);

void main() {
  testWidgets('follow requests, next episodes and activity; opening the page reads it all', (tester) async {
    final (:inbox, :social, :container) = await _pumpInbox(tester);

    expect(find.text('Notifications'), findsOneWidget);
    // Everything in one list: no sections (developer's request, 23/11/2026).
    for (final section in ['Demandes d’abonnement', 'Prochains épisodes', 'Sortis cette semaine', 'Activité']) {
      expect(find.text(section), findsNothing);
    }
    expect(find.text('Nina'), findsOneWidget);

    expect(find.text('Les Hautes Terres'), findsOneWidget);
    expect(find.text('Saison 2, épisode 5 · Le Retour'), findsOneWidget);
    expect(find.text('Demain à 21:00'), findsOneWidget);
    expect(find.text('Lupin'), findsOneWidget);
    expect(find.text('Sorti hier'), findsOneWidget);

    expect(find.text('Max aime votre avis sur Fight Club.'), findsOneWidget);
    expect(find.text('Max vous suit.'), findsOneWidget);
    expect(find.text('il y a 5 min'), findsOneWidget);
    expect(find.text('il y a 3 h'), findsOneWidget);
    // The request has its row with « Accepter » / « Refuser », not twice.
    expect(find.textContaining('demande à vous suivre'), findsNothing);
    // In order: the request, the next episode, then the most recent first.
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(find.text('Nina')), lessThan(top(find.text('Les Hautes Terres'))));
    expect(top(find.text('Les Hautes Terres')), lessThan(top(find.text('Max aime votre avis sur Fight Club.'))));
    expect(top(find.text('Max vous suit.')), lessThan(top(find.text('Lupin'))));
    expect(_pressable('Max, @max, aime votre avis sur Fight Club., il y a 5 min, non lue'), findsOneWidget);

    // Shown: everything read, the badge is cleared.
    expect(inbox.reads, 1);
    expect(container.read(unreadNotificationsProvider), 0);

    await tester.tap(_pressable('Accepter la demande de @nina'));
    await tester.pumpAndSettle();
    expect(social.calls, ['accept nina']);
    expect(find.text('@nina vous suit désormais'), findsOneWidget);
    expect(_pressable('Accepter la demande de @nina'), findsNothing);
  });

  testWidgets('a notification opens my review or the member; an episode, its show', (tester) async {
    // My review with its comments (`/avis/31`).
    await _pumpInbox(tester);
    await tester.tap(find.text('Max aime votre avis sur Fight Club.'));
    await tester.pumpAndSettle();
    expect(find.text('Avis 31'), findsOneWidget);

    await _pumpInbox(tester);
    await tester.tap(find.text('Max vous suit.'));
    await tester.pumpAndSettle();
    expect(find.text('Membre max'), findsOneWidget);

    await _pumpInbox(tester);
    await tester.tap(find.text('Les Hautes Terres'));
    await tester.pumpAndSettle();
    expect(find.text('Fiche 1399'), findsOneWidget);
  });

  testWidgets('a request declined', (tester) async {
    final social = (await _pumpInbox(tester)).social;
    await tester.tap(_pressable('Refuser la demande de @nina'));
    await tester.pumpAndSettle();
    expect(social.calls, ['decline nina']);
    expect(find.text('Demande de @nina refusée'), findsOneWidget);
  });

  testWidgets('the navigation: « Messages » with its unread number, no « Notifications »', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;

    // Phone: Accueil · Fil · Recherche · Messages · Profil (25/11/2026; « Notifications » and
    // « Paramètres » are on the profile page).
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(_shell(const Profile(id: 2, name: 'Léa')));
    await tester.pump();
    // « Notifications » is not in the navigation any more: a bell of the profile page.
    Finder tab(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
    expect(tab('Notifications, 3 notifications non lues'), findsNothing);
    final home = tester.getCenter(tab('Accueil'));
    final feed = tester.getCenter(tab('Fil d’actualité'));
    final search = tester.getCenter(tab('Recherche'));
    final messages = tester.getCenter(tab('Messages, 12 messages non lus'));
    final profile = tester.getCenter(tab('Profil'));
    expect(home.dx, lessThan(feed.dx));
    expect(feed.dx, lessThan(search.dx));
    expect(search.dx, lessThan(messages.dx));
    expect(messages.dx, lessThan(profile.dx));
    // 12 unread messages, written « 9+ ».
    expect(find.text('9+'), findsOneWidget);
    expect(tab('Paramètres'), findsNothing);

    // Large screen: not in the rail either.
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(_shell(const Profile(id: 2, name: 'Léa')));
    await tester.pump();
    expect(find.byTooltip('Notifications'), findsNothing);
    expect(_pressable('Messages, 12 messages non lus'), findsOneWidget);
    expect(find.text('9+'), findsOneWidget);

    // A profile without a username is still the account's profile; child-profile gating is gone.
    await tester.pumpWidget(_shell(const Profile(id: 3, name: 'Tom')));
    await tester.pump();
    expect(find.byTooltip('Messages'), findsOneWidget);
    expect(find.byTooltip('Recherche'), findsOneWidget);
  });

  group('models', () {
    test('a member: private account, follow status, social networks', () {
      final profile = SocialProfile.fromJson({
        'id': 7,
        'username': 'max',
        'name': 'Max',
        'is_private': true,
        'is_following': false,
        'follow_status': 'requested',
        'can_view': false,
        'social_links': [
          {'network': 'instagram', 'label': 'Instagram', 'handle': 'max.films', 'url': 'https://www.instagram.com/max.films'},
          {'network': 'website', 'label': 'Site web', 'handle': 'https://www.max.fr/', 'url': 'https://www.max.fr/'},
          // A network this app doesn't know yet: left out.
          {'network': 'mastodon', 'label': 'Mastodon', 'handle': 'max', 'url': 'https://mastodon.social/@max'},
        ],
      });
      expect(profile.isPrivate, isTrue);
      expect(profile.followStatus, FollowStatus.requested);
      expect(profile.canView, isFalse);
      expect(profile.socialLinks.map((l) => l.network), [SocialNetwork.instagram, SocialNetwork.website]);
      expect(profile.socialLinks.map((l) => l.display), ['@max.films', 'max.fr']);

      // An older API: `is_following` only, everything visible.
      final older = SocialProfile.fromJson({'id': 7, 'username': 'max', 'name': 'Max', 'is_following': true});
      expect(older.followStatus, FollowStatus.following);
      expect(older.canView, isTrue);
      expect(older.socialLinks, isEmpty);
    });

    test('the active profile: private account and networks', () {
      final profile = Profile.fromJson({
        'id': 2,
        'name': 'Léa',
        'is_private': true,
        'social_links': [
          {'network': 'x', 'label': 'X', 'handle': 'lea', 'url': 'https://x.com/lea'},
        ],
      });
      expect(profile.isPrivate, isTrue);
      expect(profile.socialLinks.single.network, SocialNetwork.x);
      expect(Profile.fromJson({'id': 2, 'name': 'Léa'}).isPrivate, isFalse);
    });

    test('a review: its id and its likes', () {
      final review = RatedItem.fromJson({
        'type': 'movie',
        'id': 550,
        'title': 'Fight Club',
        'value': 9,
        'review_id': 31,
        'likes_count': 4,
        'liked': true,
      });
      expect(review.reviewId, 31);
      expect(review.likesCount, 4);
      expect(review.liked, isTrue);
      // Rated again: still the same review, with its likes.
      expect(review.rated(const MyRating(8)).likesCount, 4);
    });

    test('a notification and an episode, from the API', () {
      final activity = Activity.fromJson({
        'id': 1,
        'type': 'review_like',
        'created_at': '2026-11-21T10:00:00+00:00',
        'read': false,
        'actor': {'id': 7, 'username': 'max', 'name': 'Max', 'avatar': null},
        'review': {
          'review_id': 31,
          'type': 'episode',
          'id': 1399,
          'title': 'Les Hautes Terres',
          'season_number': 1,
          'episode_number': 2,
          'value': 8.5,
          'poster_url': null,
        },
      });
      expect(activity.type, ActivityType.reviewLike);
      expect(activity.message, 'aime votre avis sur Les Hautes Terres · S1 · É2.');
      // The review with its comments (`/avis/:id`).
      expect(activity.path, '/avis/31');
      expect(Activity.fromJson({'id': 2, 'type': 'follow', 'actor': {'id': 7, 'username': 'max'}}).path, '/membre/max');
      expect(Activity.fromJson({'id': 3, 'type': 'new_thing', 'actor': {'id': 7}}).type, ActivityType.unknown);

      // The social network (23/11/2026): comments, a liked list, the moderation.
      final comment = Activity.fromJson({
        'id': 4,
        'type': 'review_comment',
        'actor': {'id': 7, 'username': 'max', 'name': 'Max'},
        'review': {'review_id': 31, 'type': 'movie', 'id': 550, 'title': 'Fight Club', 'value': 9},
        'comment': {'id': 5, 'body': 'Tellement d’accord !', 'contains_spoilers': false},
      });
      expect(comment.message, 'a commenté votre avis sur Fight Club : « Tellement d’accord ! »');
      expect(comment.path, '/avis/31');
      final spoiler = Activity.fromJson({
        'id': 5,
        'type': 'list_comment',
        'actor': {'id': 7, 'username': 'max', 'name': 'Max'},
        'list': {'id': 3, 'title': 'Mon top 10'},
        'comment': {'id': 6, 'body': 'La fin !', 'contains_spoilers': true},
      });
      expect(spoiler.message, 'a commenté votre liste « Mon top 10 ».');
      expect(spoiler.path, '/listes/3');
      final liked = Activity.fromJson({
        'id': 6,
        'type': 'list_like',
        'actor': {'id': 7, 'username': 'max', 'name': 'Max'},
        'list': {'id': 3, 'title': 'Mon top 10'},
      });
      expect(liked.message, 'aime votre liste « Mon top 10 ».');
      final moderation = Activity.fromJson({
        'id': 7,
        'type': 'moderation',
        'actor': {'id': 2, 'username': 'lea', 'name': 'Léa'},
        'text': 'Votre avis sur Dune a été masqué : spoiler non signalé.',
      });
      expect(moderation.actorName, 'Modération');
      expect(moderation.message, 'Votre avis sur Dune a été masqué : spoiler non signalé.');

      final episode = ShowEpisode.fromJson({
        'show': {'id': 1399, 'name': 'Les Hautes Terres', 'poster_url': null, 'backdrop_url': null},
        'season_number': 2,
        'episode_number': 5,
        'name': 'Le Retour',
        'still_url': null,
        'air_date': '2026-11-22',
        'available_at': '2026-11-22T20:00:00+00:00',
      })!;
      expect(episode.showId, 1399);
      expect(episode.label, 'Saison 2, épisode 5 · Le Retour');
      expect(episode.availableAt.isUtc, isFalse);
      expect(ShowEpisode.fromJson({'show': null, 'available_at': '2026-11-22T20:00:00Z'}), isNull);
    });

    test('dates, in French', () {
      final now = DateTime(2026, 11, 21, 15);
      expect(episodeWhen(DateTime(2026, 11, 21, 21), now), 'Aujourd’hui à 21:00');
      expect(episodeWhen(DateTime(2026, 11, 22, 8), now), 'Demain à 08:00');
      expect(episodeWhen(DateTime(2026, 11, 24, 21), now), 'Mardi 24 novembre à 21:00');
      expect(episodeWhen(DateTime(2027, 1, 1, 21), now), 'Vendredi 1er janvier 2027 à 21:00');
      expect(episodeWhen(DateTime(2026, 11, 21, 8), now), 'Sorti aujourd’hui');
      expect(episodeWhen(DateTime(2026, 11, 20, 21), now), 'Sorti hier');
      expect(episodeWhen(DateTime(2026, 11, 17, 21), now), 'Sorti mardi 17 novembre');

      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'à l’instant');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), 'il y a 5 min');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now), 'il y a 3 h');
      expect(timeAgo(DateTime(2026, 11, 20, 9), now), 'hier');
      expect(timeAgo(DateTime(2026, 11, 17, 9), now), 'il y a 4 jours');
      expect(timeAgo(DateTime(2026, 11, 2, 9), now), '2 novembre');
      expect(timeAgo(DateTime(2025, 11, 2, 9), now), '2 novembre 2025');
    });
  });
}

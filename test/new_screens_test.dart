import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/device_login.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/person_screen.dart';
import 'package:vixeo/features/profiles/avatars.dart';

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr');
const lea = Profile(id: 2, name: 'Léa');

/// Records calls instead of talking to the API.
class FakeAuth extends AuthRepository {
  FakeAuth() : super(ApiClient(token: () => null));

  int polls = 0;
  int pollsBeforeApproval = 2;
  int starts = 0;
  bool expireFirstCode = false;
  final approved = <String>[];
  final updates = <Map<String, Object?>>[];
  final verifiedPins = <String>[];

  @override
  Future<DeviceCode> startDeviceLogin() async {
    starts++;
    return DeviceCode(
      deviceCode: 'secret-$starts',
      userCode: 'K7F-29Q',
      expiresIn: const Duration(minutes: 10),
      interval: const Duration(seconds: 5),
    );
  }

  @override
  Future<({String token, User user})?> pollDeviceLogin(String deviceCode) async {
    polls++;
    if (expireFirstCode && deviceCode == 'secret-1') {
      throw const ApiException('Ce code est invalide ou a expiré.', status: 410);
    }
    return polls > pollsBeforeApproval ? (token: 'tv-token', user: davy) : null;
  }

  @override
  Future<String> lookupDeviceLogin(String userCode) async => 'Vixeo TV';

  @override
  Future<void> approveDeviceLogin(String userCode) async => approved.add(userCode);

  @override
  Future<List<Profile>> profiles() async => const [lea];

  @override
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    updates.add(fields);
    return Profile(id: profileId, name: 'Léa');
  }
}

class SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedIn, token: 't', user: davy);
}

Widget wrap(Widget child, FakeAuth auth, {List overrides = const []}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    avatarCatalogProvider.overrideWith((ref) async => const <AvatarLicense>[]),
    ...overrides.cast(),
  ],
  child: MaterialApp(
    theme: buildVixeoTheme(),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('TV: shows the code, polls, and signs in once a phone approves it', (tester) async {
    final auth = FakeAuth();
    final storage = MemorySessionStorage();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth), sessionStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const Scaffold(body: SingleChildScrollView(child: TvCodeCard())),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('K7F-29Q'), findsOneWidget);
    // Screen readers spell it out.
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Code : K, 7, F, 2, 9, Q'),
      findsOneWidget,
    );
    // No QR code (developer's request): the code is typed in the phone's app.
    expect(find.textContaining('« Connecter une TV »'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(container.read(sessionProvider).isSignedIn, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(auth.polls, 3);
    expect(container.read(sessionProvider).isSignedIn, isTrue);
    expect(storage.token, 'tv-token');
  });

  testWidgets('TV: asks a new code when the current one expired', (tester) async {
    final auth = FakeAuth()..expireFirstCode = true;
    await tester.pumpWidget(wrap(const SingleChildScrollView(child: TvCodeCard()), auth));
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(auth.starts, 2);
  });

  testWidgets('phone: approves a prefilled code', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      wrap(
        const DeviceApproveScreen(initialCode: 'k7f29q'),
        auth,
        overrides: [sessionProvider.overrideWith(SignedIn.new)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('« Vixeo TV » demande à se connecter'), findsOneWidget);
    await tester.tap(find.text('Autoriser'));
    await tester.pumpAndSettle();

    expect(auth.approved, ['K7F-29Q']);
    expect(find.text('C’est fait !'), findsOneWidget);
  });

  test('reads a person and formats dates the French way', () {
    final person = PersonDetails.fromJson({
      'id': 287,
      'name': 'Brad Pitt',
      'biography': null,
      'birthday': '1963-12-18',
      'deathday': null,
      'place_of_birth': 'Shawnee, Oklahoma, USA',
      'known_for_department': 'Acting',
      'profile_url': null,
      'known_for': [
        {'id': 550, 'type': 'movie', 'title': 'Fight Club'},
      ],
      'filmography': [
        {'id': 1, 'type': 'movie', 'title': 'F1'},
        {'id': 2, 'type': 'tv', 'title': 'Friends'},
      ],
    });

    expect(person.department, 'Interprétation');
    expect(person.lifeLine, 'Naissance : 18 décembre 1963 à Shawnee, Oklahoma, USA');
    expect(person.filmography.map((i) => i.type), [MediaType.movie, MediaType.tv]);
    expect(formatFrenchDate(DateTime(2020, 3, 1)), '1er mars 2020');
  });

  testWidgets('person page shows the biography and the filmography', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const person = PersonDetails(
      id: 287,
      name: 'Alma Meyer',
      biography: 'Actrice française.',
      knownForDepartment: 'Acting',
      knownFor: [MediaItem(id: 1, type: MediaType.movie, title: 'Nord Sauvage')],
      filmography: [
        MediaItem(id: 1, type: MediaType.movie, title: 'Nord Sauvage'),
        MediaItem(id: 2, type: MediaType.tv, title: 'Les Veilleurs'),
      ],
    );
    await tester.pumpWidget(
      wrap(
        const PersonScreen(id: 287),
        FakeAuth(),
        overrides: [
          personProvider.overrideWith((ref, id) async => person),
          sessionProvider.overrideWith(SignedIn.new),
          profilesProvider.overrideWith((ref) async => const <Profile>[]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alma Meyer'), findsOneWidget);
    expect(find.text('Interprétation'), findsOneWidget);
    expect(find.text('Actrice française.'), findsOneWidget);
    expect(find.text('Connu pour'), findsOneWidget);
    expect(find.text('Filmographie'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Les Veilleurs, série')), findsOneWidget);
  });
}

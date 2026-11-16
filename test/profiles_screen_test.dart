import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/profiles/profile_editor_screen.dart';
import 'package:vixeo/features/profiles/profiles_screen.dart';

/// The profiles of an account, in memory; records what the pages ask.
class ProfilesAuth extends AuthRepository {
  ProfilesAuth({this.parental = false, List<Profile>? profiles})
    : list = profiles ?? [const Profile(id: 1, name: 'Davy', avatar: 'lion'), const Profile(id: 2, name: 'Léa')],
      super(ApiClient(token: () => null, profileId: () => null));

  final bool parental;
  List<Profile> list;
  final created = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];
  final deleted = <(int, String?)>[];

  @override
  Future<List<Profile>> profiles() async => list;

  @override
  Future<Profile> createProfile({
    required String name,
    String? username,
    String? avatar,
    bool isKid = false,
    String? parentalPin,
  }) async {
    created.add({'name': name, 'username': username, 'avatar': avatar, 'parental_pin': parentalPin});
    final profile = Profile(id: 10 + created.length, name: name, avatar: avatar);
    list = [...list, profile];
    return profile;
  }

  @override
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    updates.add({'id': profileId, ...fields});
    if (fields['current_pin'] != null && fields['current_pin'] != '1234') {
      throw const ApiException('Code PIN incorrect.', fieldErrors: {'current_pin': ['Code PIN incorrect.']});
    }
    list = [
      for (final p in list)
        p.id != profileId
            ? p
            : Profile(
                id: p.id,
                name: fields['name'] as String? ?? p.name,
                username: fields['username'] as String? ?? p.username,
                avatar: fields.containsKey('avatar') ? fields['avatar'] as String? : p.avatar,
                hasPin: fields.containsKey('pin') ? fields['pin'] != null : p.hasPin,
              ),
    ];
    return list.firstWhere((p) => p.id == profileId);
  }

  @override
  Future<void> deleteProfile(int profileId, {String? parentalPin}) async {
    if (parental && parentalPin != '4321') {
      throw const ApiException(
        'Code PIN parental incorrect.',
        fieldErrors: {
          'parental_pin': ['Code PIN parental incorrect.'],
        },
      );
    }
    deleted.add((profileId, parentalPin));
    list = list.where((p) => p.id != profileId).toList();
  }

  @override
  Future<void> verifyParentalPin(String pin) async {
    if (pin != '4321') {
      throw const ApiException('Code PIN parental incorrect.', fieldErrors: {'pin': ['Code PIN parental incorrect.']});
    }
  }

  @override
  Future<void> verifyProfilePin(int profileId, String pin) async {
    if (pin != '1234') throw const ApiException('Code PIN incorrect.', fieldErrors: {'pin': ['Code PIN incorrect.']});
  }
}

/// Signed in, on « Qui regarde ? » (no profile chosen yet).
class Choosing extends SessionController {
  Choosing(this.parental);

  final bool parental;

  @override
  SessionState build() => SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    user: User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: parental),
  );

  Profile? chosen;

  @override
  Future<void> selectProfile(Profile profile) async => chosen = profile;
}

const _catalog = [
  AvatarLicense(
    id: 'vixeo',
    name: 'Vixeo',
    avatars: [
      AvatarDef(id: 'lion', name: 'Milo', background: Color(0xFF2EE58A)),
      AvatarDef(id: 'bear', name: 'Bram', background: Color(0xFF15524A)),
    ],
  ),
];

void main() {
  late ProfilesAuth auth;
  late Choosing session;

  Future<void> pump(WidgetTester tester, {bool parental = false, List<Profile>? profiles}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    auth = ProfilesAuth(parental: parental, profiles: profiles);
    session = Choosing(parental);
    final router = GoRouter(
      initialLocation: '/profils',
      routes: [
        GoRoute(path: '/profils', builder: (_, _) => const ProfilesScreen()),
        GoRoute(path: ProfileEditorScreen.newLocation, builder: (_, _) => const ProfileEditorScreen()),
        GoRoute(
          path: '/profils/modifier/:id',
          builder: (_, state) => ProfileEditorScreen(profileId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => session),
          authRepositoryProvider.overrideWithValue(auth),
          avatarCatalogProvider.overrideWith((ref) async => _catalog),
        ],
        child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.bySemanticsLabel(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('« Qui regarde ? »: the profiles and « Gérer les profils », no sign-out', (tester) async {
    await pump(tester);

    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('Davy'), findsOneWidget);
    expect(find.text('Léa'), findsOneWidget);
    expect(find.text('Gérer les profils'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsNothing);
    expect(find.text('Ajouter un profil'), findsNothing);

    await tester.tap(find.text('Léa'));
    await tester.pumpAndSettle();
    expect(session.chosen?.name, 'Léa');
  });

  testWidgets('managing: a pencil on each profile, « Ajouter un profil », « Terminé »', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    expect(find.text('Terminé'), findsOneWidget);
    expect(find.text('Ajouter un profil'), findsOneWidget);
    expect(find.bySemanticsLabel('Modifier le profil de Davy'), findsOneWidget);

    // A tap edits instead of opening.
    await tester.tap(find.text('Davy'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le profil'), findsOneWidget);
    expect(session.chosen, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminé'));
    await tester.pumpAndSettle();
    expect(find.text('Gérer les profils'), findsOneWidget);
  });

  testWidgets('no « Ajouter un profil » with 5 profiles', (tester) async {
    await pump(tester, profiles: [for (var i = 1; i <= 5; i++) Profile(id: i, name: 'P$i')]);
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un profil'), findsNothing);
  });

  testWidgets('a protected profile asks its PIN on the keypad', (tester) async {
    await pump(tester, profiles: [const Profile(id: 1, name: 'Davy', hasPin: true)]);

    await tester.tap(find.text('Davy'));
    await tester.pumpAndSettle();
    expect(find.text('Saisir le code PIN'), findsOneWidget);
    await typePin(tester, '0000');
    expect(find.text('Code PIN incorrect.'), findsOneWidget);
    expect(session.chosen, isNull);

    await typePin(tester, '1234');
    expect(session.chosen?.name, 'Davy');
  });

  testWidgets('adds a profile: the name, an avatar, then « Créer un profil »', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un profil'));
    await tester.pumpAndSettle();

    expect(find.text('Ajouter un profil'), findsWidgets);
    expect(find.text('Nouveau profil'), findsOneWidget);
    // No name yet: nothing to create.
    await tester.tap(find.text('Créer un profil'));
    await tester.pump();
    expect(auth.created, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Nom du profil'), 'Tom');
    await tester.pump();
    // The preview follows the name.
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Tom'), findsOneWidget);
    // The pseudo, chosen at once.
    await tester.enterText(find.widgetWithText(TextField, 'Pseudo'), 'Tom_42');
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Text && w.data == '@Tom_42'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Bram')));
    await tester.pump();
    expect(find.bySemanticsLabel('Bram, choisi'), findsOneWidget);

    await tester.ensureVisible(find.text('Créer un profil'));
    await tester.tap(find.text('Créer un profil'));
    await tester.pumpAndSettle();

    expect(auth.created.single, {'name': 'Tom', 'username': 'tom_42', 'avatar': 'bear', 'parental_pin': null});
    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('Tom'), findsOneWidget);
  });

  testWidgets('parental control on: creating asks the parental PIN', (tester) async {
    await pump(tester, parental: true);
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un profil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nom du profil'), 'Tom');
    await tester.pump();
    await tester.ensureVisible(find.text('Créer un profil'));
    await tester.tap(find.text('Créer un profil'));
    await tester.pumpAndSettle();

    expect(find.text('Code PIN parental'), findsOneWidget);
    await typePin(tester, '4321');
    expect(auth.created.single['parental_pin'], '4321');
  });

  testWidgets('changes a profile: name and avatar, then a PIN', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Davy'));
    await tester.pumpAndSettle();

    // No « Avatar : … » line (developer's request).
    expect(find.textContaining('Avatar :'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Nom du profil'), 'David');
    // The pseudo can be changed too.
    await tester.enterText(find.widgetWithText(TextField, 'Pseudo'), 'david_b');
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Text && w.data == '@david_b'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Bram')));
    await tester.pump();

    // The PIN: typed twice.
    await tester.ensureVisible(find.text('Ajouter un code PIN'));
    await tester.tap(find.text('Ajouter un code PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Saisir un nouveau code PIN'), findsOneWidget);
    await typePin(tester, '1234');
    expect(find.text('Saisissez-le une seconde fois'), findsOneWidget);
    await typePin(tester, '1234');
    expect(auth.updates.last, {'id': 1, 'pin': '1234'});
    expect(find.text('Ce profil est protégé par un code PIN.'), findsOneWidget);

    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(auth.updates.last, {'id': 1, 'name': 'David', 'username': 'david_b', 'avatar': 'bear'});
    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('David'), findsOneWidget);
  });

  testWidgets('removes a PIN with the current one', (tester) async {
    await pump(
      tester,
      profiles: [const Profile(id: 1, name: 'Davy', hasPin: true), const Profile(id: 2, name: 'Léa')],
    );
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Davy'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Retirer le code PIN'));
    await tester.tap(find.text('Retirer le code PIN'));
    await tester.pumpAndSettle();
    await typePin(tester, '9999');
    expect(find.text('Code PIN incorrect.'), findsOneWidget);
    await typePin(tester, '1234');
    expect(auth.updates.last, {'id': 1, 'pin': null, 'current_pin': '1234'});
    expect(find.text('Ajouter un code PIN'), findsOneWidget);
  });

  testWidgets('deletes a profile after a confirmation (parental PIN when on)', (tester) async {
    await pump(tester, parental: true);
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Léa'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Supprimer le profil'));
    await tester.tap(find.text('Supprimer le profil'));
    await tester.pumpAndSettle();
    expect(find.text('Toutes les données de « Léa » seront définitivement supprimées.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
    await tester.pumpAndSettle();
    await typePin(tester, '4321');

    expect(auth.deleted.single, (2, '4321'));
    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('Léa'), findsNothing);
  });

  testWidgets('the last profile can’t be deleted', (tester) async {
    await pump(tester, profiles: [const Profile(id: 1, name: 'Davy')]);
    await tester.tap(find.text('Gérer les profils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Davy'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer le profil'), findsNothing);
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/common.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/profiles/covers.dart';
import 'package:vixeo/features/profiles/profile_editor_screen.dart';
import 'package:vixeo/features/profiles/profile_photo.dart';
import 'package:vixeo/features/profiles/profiles_screen.dart';
import 'package:vixeo/features/profiles/settings_rows.dart';
import 'package:vixeo/features/social/social_links.dart';

/// The profiles of an account, in memory; records what the pages ask.
class ProfilesAuth extends AuthRepository {
  ProfilesAuth({this.parental = false, List<Profile>? profiles})
    : list = profiles ?? [const Profile(id: 1, name: 'Davy', avatar: 'lion'), const Profile(id: 2, name: 'Léa')],
      super(ApiClient(token: () => null, profileId: () => null));

  final bool parental;
  List<Profile> list;
  final created = <Map<String, Object?>>[];
  final restrictions = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];
  final deleted = <(int, String?)>[];
  final photos = <(int, int)>[];
  final photoRemovals = <int>[];
  final createdCovers = <String?>[];
  final covers = <(int, int)>[];
  final coverRemovals = <int>[];

  @override
  Future<Profile> uploadProfileCover(int profileId, Uint8List png) async {
    covers.add((profileId, png.length));
    return list.firstWhere((p) => p.id == profileId);
  }

  @override
  Future<Profile> deleteProfileCover(int profileId) async {
    coverRemovals.add(profileId);
    return list.firstWhere((p) => p.id == profileId);
  }

  @override
  Future<Profile> uploadProfilePhoto(int profileId, Uint8List png) async {
    photos.add((profileId, png.length));
    return _withPhoto(profileId, 'https://api.vixeo.test/api/v1/profile-photos/new.webp');
  }

  @override
  Future<Profile> deleteProfilePhoto(int profileId) async {
    photoRemovals.add(profileId);
    return _withPhoto(profileId, null);
  }

  Profile _withPhoto(int profileId, String? url) {
    list = [
      for (final p in list)
        p.id != profileId ? p : Profile(id: p.id, name: p.name, username: p.username, avatar: p.avatar, photoUrl: url),
    ];
    return list.firstWhere((p) => p.id == profileId);
  }

  @override
  Future<List<Profile>> profiles() async => list;

  @override
  Future<Profile> createProfile({
    required String name,
    String? username,
    String? avatar,
    String? cover,
    bool isKid = false,
    int? maxAgeRating,
    bool allowUnrated = false,
    String? parentalPin,
  }) async {
    created.add({'name': name, 'username': username, 'avatar': avatar, 'parental_pin': parentalPin});
    createdCovers.add(cover);
    restrictions.add({'is_kid': isKid, 'max_age_rating': maxAgeRating, 'allow_unrated': allowUnrated});
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

const _covers = [
  CoverStyle(
    id: 'degrades',
    name: 'Dégradés',
    covers: [
      CoverDef(id: 'aurore', name: 'Aurore', pattern: CoverPattern.linear, colors: [Color(0xFF03140A), Color(0xFF2EE58A)]),
    ],
  ),
  CoverStyle(
    id: 'cinema',
    name: 'Cinéma',
    covers: [
      CoverDef(
        id: 'rideau',
        name: 'Rideau',
        pattern: CoverPattern.curtain,
        colors: [Color(0xFF2A0508), Color(0xFF8C1C24), Color(0xFFD4A017)],
      ),
    ],
  ),
];

void main() {
  late ProfilesAuth auth;
  late Choosing session;
  late GoRouter router;

  /// On « Qui regarde ? ».
  Future<void> pump(
    WidgetTester tester, {
    bool parental = false,
    List<Profile>? profiles,
  }) async {
    // Tall: the whole editor fits (the scrolled positions are laid out at the next frame).
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    auth = ProfilesAuth(parental: parental, profiles: profiles);
    session = Choosing(parental);
    router = GoRouter(
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
          coverCatalogProvider.overrideWith((ref) async => _covers),
        ],
        child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// « Modifier mon profil » (« ⋮ » of the profile page): the editor, over « Qui regarde ? ».
  Future<void> edit(WidgetTester tester, int id) async {
    router.push(ProfileEditorScreen.editLocation(id));
    await tester.pumpAndSettle();
  }

  /// « Ajouter » of « Qui regarde ? ».
  Future<void> add(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Ajouter un profil'));
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.bySemanticsLabel(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('« Qui regarde ? »: the profiles and « Ajouter », no management, no sign-out', (tester) async {
    await pump(tester);

    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('Davy'), findsOneWidget);
    expect(find.text('Léa'), findsOneWidget);
    // A profile is changed from the « ⋮ » of its page.
    expect(find.text('Gérer les profils'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Modifier le profil')), findsNothing);
    expect(find.text('Se déconnecter'), findsNothing);
    // « Ajouter » after the profiles.
    expect(find.text('Ajouter'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajouter un profil'), findsOneWidget);

    await tester.tap(find.text('Léa'));
    await tester.pumpAndSettle();
    expect(session.chosen?.name, 'Léa');
  });

  testWidgets('« Ajouter » opens « Ajouter un profil », back to « Qui regarde ? »', (tester) async {
    await pump(tester);
    await add(tester);

    expect(find.text('Ajouter un profil'), findsWidgets);
    expect(find.text('Nouveau profil'), findsOneWidget);
    // No page of its own yet: no biography nor networks.
    expect(find.widgetWithText(TextField, 'Biographie'), findsNothing);
    expect(session.chosen, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Qui regarde ?'), findsOneWidget);
  });

  testWidgets('no « Ajouter » with 5 profiles', (tester) async {
    await pump(tester, profiles: [for (var i = 1; i <= 5; i++) Profile(id: i, name: 'P$i')]);
    expect(find.text('P5'), findsOneWidget);
    expect(find.text('Ajouter'), findsNothing);
    expect(find.bySemanticsLabel('Ajouter un profil'), findsNothing);
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
    await add(tester);

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
    await tester.pump();
    await tester.tap(find.text('Créer un profil'));
    await tester.pumpAndSettle();

    expect(auth.created.single, {'name': 'Tom', 'username': 'tom_42', 'avatar': 'bear', 'parental_pin': null});
    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('Tom'), findsOneWidget);
  });

  testWidgets('parental control on: creating asks the parental PIN', (tester) async {
    await pump(tester, parental: true);
    await add(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nom du profil'), 'Tom');
    await tester.pump();
    await tester.ensureVisible(find.text('Créer un profil'));
    await tester.pump();
    await tester.tap(find.text('Créer un profil'));
    await tester.pumpAndSettle();

    expect(find.text('Code PIN parental'), findsOneWidget);
    await typePin(tester, '4321');
    expect(auth.created.single['parental_pin'], '4321');
  });

  testWidgets('changes a profile: name and avatar, then a PIN', (tester) async {
    await pump(tester);
    await edit(tester, 1);

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
    await tester.pump();
    await tester.tap(find.text('Ajouter un code PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Saisir un nouveau code PIN'), findsOneWidget);
    await typePin(tester, '1234');
    expect(find.text('Saisissez-le une seconde fois'), findsOneWidget);
    await typePin(tester, '1234');
    expect(auth.updates.last, {'id': 1, 'pin': '1234'});
    expect(find.text('Ce profil est protégé par un code PIN.'), findsOneWidget);

    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
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
    await edit(tester, 1);

    await tester.ensureVisible(find.text('Retirer le code PIN'));
    await tester.pump();
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
    await edit(tester, 2);

    await tester.ensureVisible(find.text('Supprimer le profil'));
    await tester.pump();
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

  testWidgets('adds a profile with an age limit: no « Profil enfant »', (tester) async {
    await pump(tester);
    await add(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nom du profil'), 'Tom');
    await tester.pump();

    expect(find.text('Restrictions'), findsOneWidget);
    expect(find.text('Profil enfant'), findsNothing);
    // Unrated titles: only with an age limit.
    await tester.ensureVisible(find.text('Titres sans classification'));
    await tester.pump();
    await tester.tap(find.text('Titres sans classification'));
    await tester.pump();
    SettingsSwitchRow unrated() =>
        tester.widget<SettingsSwitchRow>(find.widgetWithText(SettingsSwitchRow, 'Titres sans classification'));
    expect(unrated().value, isFalse);
    expect(unrated().onChanged, isNull);

    await tester.tap(find.text('Âge maximum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12 ans'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Titres sans classification'));
    await tester.pump();
    await tester.tap(find.text('Titres sans classification'));
    await tester.pump();
    expect(unrated().value, isTrue);

    await tester.ensureVisible(find.text('Créer un profil'));
    await tester.pump();
    await tester.tap(find.text('Créer un profil'));
    await tester.pumpAndSettle();
    expect(auth.restrictions.single, {'is_kid': false, 'max_age_rating': 12, 'allow_unrated': true});
  });

  testWidgets('a former kid profile shows its 10-year limit, kept explicit when changed', (tester) async {
    await pump(
      tester,
      profiles: [const Profile(id: 1, name: 'Davy'), const Profile(id: 2, name: 'Léa', isKid: true)],
    );
    // No « Enfant » badge either.
    expect(find.text('Enfant'), findsNothing);
    await edit(tester, 2);
    // A child's profile has no page: no biography nor networks.
    expect(find.widgetWithText(TextField, 'Biographie'), findsNothing);
    expect(find.text('Réseaux sociaux'), findsNothing);

    expect(find.bySemanticsLabel('Âge maximum : 10 ans'), findsOneWidget);
    await tester.ensureVisible(find.text('Titres sans classification'));
    await tester.pump();
    await tester.tap(find.text('Titres sans classification'));
    await tester.pump();
    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();

    expect(auth.updates.last, {'id': 2, 'is_kid': false, 'max_age_rating': 10, 'allow_unrated': true});
  });

  testWidgets('changing restrictions asks the parental PIN and sends it', (tester) async {
    await pump(tester, parental: true);
    await edit(tester, 2);

    await tester.ensureVisible(find.text('Âge maximum'));
    await tester.pump();
    await tester.tap(find.text('Âge maximum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12 ans'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Âge maximum : 12 ans'), findsOneWidget);

    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(find.text('Nécessaire pour changer les restrictions'), findsOneWidget);
    await typePin(tester, '4321');

    expect(auth.updates.last, {'id': 2, 'max_age_rating': 12, 'parental_pin': '4321'});
    expect(find.text('Qui regarde ?'), findsOneWidget);
  });

  testWidgets('« Modifier le profil »: biography, networks and « Compte privé » of its page', (tester) async {
    await pump(
      tester,
      profiles: [
        const Profile(
          id: 1,
          name: 'Davy',
          username: 'davy',
          bio: 'Fan de SF.',
          socialLinks: [
            SocialLink(network: SocialNetwork.instagram, handle: 'davy', url: 'https://instagram.com/davy'),
          ],
        ),
        const Profile(id: 2, name: 'Léa'),
      ],
    );
    await edit(tester, 1);

    expect(find.widgetWithText(TextField, 'Fan de SF.'), findsOneWidget);
    expect(find.text('Réseaux sociaux'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'davy'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, 'Fan de SF.'), 'Fan de science-fiction.');
    await tester.ensureVisible(find.widgetWithText(TextField, 'Letterboxd'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Letterboxd'), 'davyb');
    // Instagram emptied: removed.
    await tester.enterText(find.widgetWithText(TextField, 'Instagram'), '');
    await tester.ensureVisible(find.text('Compte privé'));
    await tester.pump();
    await tester.tap(find.text('Compte privé'));
    await tester.pump();

    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    final sent = auth.updates.last;
    expect(sent['id'], 1);
    expect(sent['bio'], 'Fan de science-fiction.');
    expect(sent['is_private'], isTrue);
    final links = sent['social_links']! as Map<String, Object?>;
    expect(links['instagram'], isNull);
    expect(links['letterboxd'], 'davyb');
    expect(links.length, SocialNetwork.values.length);
    expect(find.text('Qui regarde ?'), findsOneWidget);
  });

  testWidgets('the last profile can’t be deleted', (tester) async {
    await pump(tester, profiles: [const Profile(id: 1, name: 'Davy')]);
    await edit(tester, 1);
    expect(find.text('Supprimer le profil'), findsNothing);
  });

  testWidgets('a photo instead of the avatar: « Retirer la photo », or an avatar chosen', (tester) async {
    const photo = 'https://api.vixeo.test/api/v1/profile-photos/davy.webp';
    bool showsPhoto() => find.byWidgetPredicate((w) => w is NetImage && w.url == photo).evaluate().isNotEmpty;
    final profiles = [
      const Profile(id: 1, name: 'Davy', avatar: 'lion', photoUrl: photo),
      const Profile(id: 2, name: 'Léa'),
    ];
    await pump(tester, profiles: profiles);
    // « Qui regarde ? » shows the photo.
    expect(showsPhoto(), isTrue);
    await edit(tester, 1);

    expect(find.text('Photo de profil'), findsOneWidget);
    expect(find.text('Votre photo est affichée à la place de l’avatar. Choisir un avatar la retire.'), findsOneWidget);
    expect(find.text('Changer la photo'), findsOneWidget);
    // With the photo, no avatar is marked as chosen.
    expect(find.bySemanticsLabel(RegExp(r'^Milo, choisi')), findsNothing);
    await tester.ensureVisible(find.text('Retirer la photo'));
    await tester.pump();
    await tester.tap(find.text('Retirer la photo'));
    await tester.pump();
    expect(find.text('Importer une photo'), findsOneWidget);
    expect(find.text('Retirer la photo'), findsNothing);
    expect(showsPhoto(), isFalse);
    expect(find.bySemanticsLabel(RegExp(r'^Milo, choisi')), findsOneWidget);

    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(auth.photoRemovals, [1]);
    expect(auth.photos, isEmpty);
  });

  testWidgets('an avatar chosen replaces the photo', (tester) async {
    await pump(
      tester,
      profiles: [
        const Profile(id: 1, name: 'Davy', avatar: 'lion', photoUrl: 'https://api.vixeo.test/api/v1/profile-photos/d.webp'),
        const Profile(id: 2, name: 'Léa'),
      ],
    );
    await edit(tester, 1);
    await tester.ensureVisible(find.text('Retirer la photo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.bySemanticsLabel(RegExp(r'^Bram')));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Bram')));
    await tester.pump();
    expect(find.text('Retirer la photo'), findsNothing);
    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(auth.updates.last, {'id': 1, 'avatar': 'bear'});
    expect(auth.photoRemovals, [1]);
  });

  testWidgets('a cover of the catalog by style, or an image of its own; a new profile gets one at random', (
    tester,
  ) async {
    await pump(
      tester,
      profiles: [
        const Profile(
          id: 1,
          name: 'Davy',
          avatar: 'lion',
          cover: 'aurore',
          coverUrl: 'https://api.vixeo.test/api/v1/profile-covers/davy.webp',
        ),
        const Profile(id: 2, name: 'Léa', cover: 'aurore'),
      ],
    );
    await edit(tester, 1);

    expect(find.text('Couverture'), findsOneWidget);
    expect(find.text('Dégradés'), findsOneWidget);
    expect(find.text('Cinéma'), findsOneWidget);
    // With its image, no cover of the catalog is marked.
    expect(find.text('Changer l’image'), findsOneWidget);
    expect(find.bySemanticsLabel('Couverture Aurore, choisie'), findsNothing);

    // A cover chosen replaces the image.
    await tester.ensureVisible(find.bySemanticsLabel(RegExp('^Couverture Rideau')));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp('^Couverture Rideau')));
    await tester.pump();
    expect(find.bySemanticsLabel('Couverture Rideau, choisie'), findsOneWidget);
    expect(find.text('Retirer l’image'), findsNothing);
    await tester.ensureVisible(find.text('Enregistrer les modifications'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(auth.updates.last, {'id': 1, 'cover': 'rideau'});
    expect(auth.coverRemovals, [1]);
    expect(auth.covers, isEmpty);

    // A new profile (« Ajouter », back on « Qui regarde ? »): a cover of the catalog, at random.
    await add(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nom du profil'), 'Tom');
    await tester.pump();
    await tester.ensureVisible(find.text('Créer un profil'));
    await tester.pump();
    await tester.tap(find.text('Créer un profil'));
    await tester.pumpAndSettle();
    expect(auth.createdCovers.single, isIn(['aurore', 'rideau']));
  });

  testWidgets('« Cadrer la couverture » gives back a 3:1 banner of 1,500 × 500 pixels', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 900, 900), Paint()..color = const Color(0xFF2EE58A));
      final image = await recorder.endRecording().toImage(900, 900);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    Uint8List? framed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVixeoTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => framed = await framePhoto(context, png!, shape: FramingShape.cover),
                child: const Text('Cadrer'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cadrer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cadrer la couverture'), findsOneWidget);
    expect(find.text('Déplacez l’image et zoomez pour la cadrer.'), findsOneWidget);

    await tester.tap(find.text('Utiliser cette image'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(framed, isNotNull);
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(framed!);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    });
    expect(size, (1500, 500));
  });

  testWidgets('« Cadrer la photo » gives back a square of 512 pixels', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A landscape photo: red on the left, blue on the right.
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, 300, 400), Paint()..color = const Color(0xFFFF0000))
        ..drawRect(const Rect.fromLTWH(300, 0, 300, 400), Paint()..color = const Color(0xFF0000FF));
      final image = await recorder.endRecording().toImage(600, 400);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    Uint8List? framed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVixeoTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => framed = await framePhoto(context, png!),
                child: const Text('Cadrer'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cadrer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The photo is decoded by the engine.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cadrer la photo'), findsOneWidget);
    expect(find.text('Déplacez la photo et zoomez pour la cadrer.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Zoomer'));
    await tester.pump();
    await tester.tap(find.text('Utiliser cette photo'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(framed, isNotNull);
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(framed!);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    });
    expect(size, (512, 512));
  });
}

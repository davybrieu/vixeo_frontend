# Vixeo — appli Flutter (vixeo_frontend)

Appli **Vixeo** (media center) pour Android, Android TV / Google TV et Windows, puis iOS, avec
une seule base de code. **Plus de version web** (demande du développeur, 20/11/2026 : ni build
web, ni dossier `web/`, ni code propre au navigateur ; ne pas la réintroduire). L'API Laravel est dans
[`davybrieu/vixeo_backend`](https://github.com/davybrieu/vixeo_backend).

**Charte graphique : [`docs/charte-graphique.md`](docs/charte-graphique.md)** (couleurs, textes,
espacements, composants, focus) : à suivre pour tout écran ; valeurs dans `core/theme.dart` et
`core/design.dart`.

**Lire d'abord [`docs/CONTEXT.md`](docs/CONTEXT.md)** (copie de celui de l'API) : décisions produit,
périmètre légal (§3 : ce qui est hors périmètre ne doit pas être implémenté), sécurité (§6).

**Écarté par le développeur** (ne pas proposer) : import IPTV / M3U / Xtream, radio, replays.

**Distribution Android** (décision du développeur, ne plus poser la question) : **pas de Play
Store**. L'appli Android (téléphones, tablettes, Android TV / Google TV) est distribuée en
**APK signé** depuis le site (`www.vixeo.app/#installer`, dans `vixeo_backend`). Conséquences :
- chaque version est signée avec la **même clé de release** (keystore hors du dépôt, dans les
  secrets) : sinon Android refuse d'installer la mise à jour par-dessus l'ancienne version ;
- les mises à jour passent par la vérification intégrée à l'appli (`GET /app/update`), pas par
  un store ;
- vérification des développeurs Android par Google : obligatoire hors Play Store dans 4 pays
  depuis le 30/09/2026, prévue partout en 2027 : enregistrer le développeur dans l'Android
  Developer Console avant.

**Distribution Windows** (demande du développeur, 20/11/2026) : **installateur Inno Setup**
(`windows/installer/vixeo.iss`, `vixeo-setup-<build>.exe`, pour l'utilisateur, sans droits
d'administrateur), publié en release GitHub `windows-<build>` par la CI et téléchargé depuis le
site ; pas de Microsoft Store ; **non signé** pour l'instant (SmartScreen). Détails :
[`docs/windows-release.md`](docs/windows-release.md).

Design de référence (canevas) : https://claude.ai/artifact/ESe8nVYEhsSdPbzeV8UdNc
(écrans téléphone + TV, charte graphique).

## Le développeur

Débutant en Flutter / Dart, à l'aise en PHP / Laravel et JS / Vue : expliquer les concepts Flutter
quand ils apparaissent (widgets, état, focus, plateformes), avec des parallèles Vue / Laravel.

## Langue

- Échanges, textes de l'interface, documentation : **français**.
- Code, noms, messages de commit : anglais.

## Commandes

```bash
flutter pub get
flutter analyze                    # doit rester propre
flutter test                       # tests unitaires et de widgets
dart format lib test               # largeur 120 (analysis_options.yaml)

# Lancer contre une API locale (php artisan serve dans vixeo_backend)
flutter run -d windows --dart-define=API_URL=http://localhost:8000
flutter run -d <android> --dart-define=API_URL=http://10.0.2.2:8000   # émulateur Android
flutter build windows --release --dart-define=API_URL=https://api.<domaine> \
  --dart-define=PUBLISHER_NAME="…" --dart-define=SUPPORT_EMAIL=support@<domaine>
```

Une version Release refuse de démarrer sans `API_URL` en `https://`, ni sans `PUBLISHER_NAME` et
`SUPPORT_EMAIL` (`AppConfig.configurationError`).

Dans un conteneur Claude Code cloud, Flutter n'est pas préinstallé : voir le script de
`docs/CONTEXT.md` §7 (clone du canal stable dans `/opt/flutter`). Pas de SDK Android, ni de
Windows, ni de Xcode : seuls `flutter analyze` et les tests se vérifient dans le conteneur ; les
APK et l'installateur Windows sont compilés par la CI.

## Structure

```
lib/
  main.dart, app.dart, router.dart   entrée, thème, raccourcis télécommande, routes
  core/
    config.dart                      API_URL (--dart-define), contrôle de la configuration en Release
    features.dart                    fonctions masquées pour l'instant (TV en direct : liveTvProvider)
    legal.dart                       éditeur et adresse de support (--dart-define)
    theme.dart                       couleurs (VxColors), polices Sora / Inter (VxText)
    device/layout.dart               téléphone / tablette / grand écran, détection TV, échelle TV
    api/                             client HTTP (dio), erreurs en français, stockage du jeton,
                                     temps réel Reverb (realtime.dart : une WebSocket, un canal par sujet)
    widgets/                         VxFocusable (focus TV), boutons, images, états vides / erreur
  features/
    auth/        page d'accueil de l'appli (« Continuer avec Google / Apple / l'e-mail »), connexion par
                 e-mail, Google et Apple (social_sign_in.dart), inscription, mot de passe oublié, session,
                 connexion TV par code (device_login.dart : carte TV + page /tv)
    account/     Mon compte (export, suppression), appareils connectés
    updates/     vérification et installation des mises à jour Android / Windows (UpdateGate,
                 écrans, ApkInstaller : APK ou installateur Windows)
    profiles/    profil unique par compte, édition du profil social, avatars, photo et couverture
                 (profile_photo.dart : cadrage, covers.dart : couvertures dessinées)
    catalog/     modèles TMDb, accueil, fiche film / série, page personne, cartes et rangées
    library/     synchro par profil (« À voir », J’aime ❤, personnes suivies, vus, « Continuer à
                 regarder »), page « À voir » (aussi « Mes J’aime » et « Mes titres vus »),
                 bouton « Ajouter à une liste »
    search/      recherche (par texte, ou par filtres seuls), filtres (type, genre, années, note) et tri,
                 recherches récentes synchronisées (search_history.dart)
    playback/    lecteur (PlayerScreen, commun à toutes les plateformes), moteurs de lecture
                 (engine/ : natif Android / iOS, media_kit sur Windows), sous-titres WebVTT,
                 moments à passer (TheIntroDB) et sous-titres (OpenSubtitles) via l'API
    tv/          TV en direct : chaînes et catégories de l'API (rangée, grille de la recherche),
                 lecteur d'un flux (HLS) ; pas de page à part
    shell/       navigation : onglets en bas (téléphone), rail à gauche (TV, tablette, ordi)
    tmdb/        avis du profil (nom historique) : notes et commentaires (fenêtre,
                 boutons, onglet « Avis »)
    ratings/     notes IMDb (jeux de données importés par l'API) sinon TMDb ; fenêtre « Notes » :
                 charge aussi à l'ouverture les notes externes MDBList (Trakt, Letterboxd, Rotten
                 Tomatoes, Metacritic, MyAnimeList)
    notifications/  page « Notifications » de la navigation (`InboxScreen`, `inbox.dart` : demandes
                 d'abonnement, prochains épisodes, activité, pastille), notifications push (FCM) :
                 réglages (`NotificationsScreen`), inscription auprès de l'API (`PushRegistration`),
                 affichage et appui (`NotificationsGate`)
    social/      pages de profil (`ProfileView`), réseaux sociaux (`social_links.dart`), compte
                 privé et demandes d'abonnement, J'aime sur les avis (`review_likes.dart`)
    messages/    messagerie : modèles, dépôt et providers (`messages.dart`, canal temps réel
                 `conversationChannel`), « Messages » (`conversations_screen.dart`), une conversation
                 (`conversation_screen.dart`), créer / gérer un groupe (`group_screen.dart`)
    network/     réseau social des films et séries : modèles, dépôt et providers (`network.dart`),
                 cartes (`widgets.dart`), menus (`actions.dart` : signaler, bloquer, masquer, listes,
                 envoyer à un ami), « Fil d'actualité » (`feed_screen.dart`), avis et commentaires
                 (`review_screen.dart`, `comments.dart`), listes (`list_screen.dart`), activité,
                 « À voir » et bilan (`profile_sections.dart`, `profile_pages.dart`), fiche sociale
                 (`title_social.dart`), image à partager (`share_image.dart`), premier lancement
                 (`onboarding_screen.dart`), note en fin de lecture (`rate_prompt.dart`)
```

## Conventions

- **Material** : `import 'package:material_ui/material_ui.dart'` (paquet `material_ui`), **jamais
  `package:flutter/material.dart`** (déprécié depuis Flutter 3.47, migré le 21/11/2026, demande du
  développeur) ; les traductions (`GlobalMaterialLocalizations`) viennent aussi de `material_ui`.
  go_router cherche le `MaterialApp` de `material_ui` pour bâtir ses pages.
- **État** : Riverpod 3 (`Provider`, `FutureProvider.family`, `Notifier`, `AsyncNotifier`), sans
  génération de code. La session charge automatiquement l'unique profil du compte ; les données
  sont synchronisées pour cette identité, sans sélection ni filtrage par âge.
- **Jamais d'ancienne adresse** (demande du développeur, 23/11/2026) : quand une page change
  d'adresse ou disparaît, l'ancienne adresse est supprimée (ni redirection ni alias) ; supprimés
  le 23/11/2026 : `/@pseudo`, `/films`, `/series`, `/tv-live`, `/profils/gestion`,
  `/profil/avatar`, `/profil/controle-parental`, `/profil/code-pin`, `/profil/connexions`,
  `/profil/tmdb`, `/profil/notes`, `/profil/social/favoris`.
- **Navigation** : go_router. La connexion est la page d'entrée ; le routeur redirige vers
  `/connexion` tant qu'on n'est pas connecté, puis vers `/accueil` après authentification.
  Le routeur n'écoute que le statut de connexion et la présence du profil unique : modifier le profil
  (avatar…) ne doit pas reconstruire les pages. Exception : `/tv` (« Connecter une TV ») ne
  demande pas de profil ; ouvert sans être connecté, il est mémorisé et rouvert juste après la
  connexion.
  `/connexion/email` et `/mot-de-passe-oublie` sont des pages de connexion.
- **Page d'accueil (connexion)** (`/connexion`, `LoginScreen`, demande du développeur, 25/11/2026,
  d'après une autre appli de films) : fond sombre éclairé de vert, logo en haut, accroche au
  milieu (« Regardez vos films et vos séries / Partagez vos avis avec la communauté »), en bas
  trois grands boutons arrondis : **« Continuer avec Google »** (blanc, « G » officiel),
  **« Continuer avec Apple »** et **« Continuer avec l’e-mail »** (`EmailLoginScreen`,
  `/connexion/email` : adresse, mot de passe, « Mot de passe oublié ? », « Créer un compte » ;
  Retour : l'accueil ; l'inscription et le mot de passe oublié reviennent à `/connexion/email`),
  puis « Vixeo ne reçoit de Google ou d’Apple que votre nom et votre adresse e-mail. » ;
  « Continuer en invité » en haut à droite. **Pas de ligne « vous acceptez nos Conditions… »** :
  ni conditions d'utilisation ni politique de confidentialité de l'appli pour l'instant. Grand
  écran : boutons à côté de `TvCodeCard` ; **TV : pas de Google ni d'Apple** (pas de navigateur),
  l'e-mail et le code. Logos : `brand/sign-in` → `assets/images/sign_in/` (`brand/tools/sign_in_logos.py`).
  **Connexion Google / Apple** (`social_sign_in.dart` ; API : `vixeo_backend/docs/connexion-sociale.md`) :
  **dans un navigateur**, l'API est le client OAuth (aucun identifiant Google ou Apple dans
  l'appli) ; secret PKCE gardé en mémoire (`pkceVerifier`, `pkceChallenge`), navigateur ouvert
  sur `/auth/social/{google|apple}`, retour avec `?code=` puis `POST /auth/social/token`.
  `BrowserAuthorizer` (`browserAuthorizerProvider`, null sur TV et dans les tests) : Android / iOS
  `CustomTabAuthorizer` (`flutter_web_auth_2`, onglet Chrome, retour par `app.vixeo://auth` :
  `CallbackActivity` du manifeste) ; Windows `LoopbackAuthorizer` (navigateur par défaut, petit
  serveur de l'appli sur `http://127.0.0.1:{port}/auth`, puis Vixeo revient devant ; la webview du
  paquet est remplacée par son stub, `third_party/`, `dependency_overrides`). `GET /auth/social`
  (`socialProvidersProvider`) : un fournisseur sans réglages sur le serveur le dit tout de suite
  (« La connexion avec Apple n’est pas encore disponible. »). Compte sans mot de passe
  (`User.hasPassword`, `providers`) : « Mon compte » propose « Créer un mot de passe », supprime
  le compte sans mot de passe et demande d'en créer un pour changer d'adresse. Tests :
  `test/login_screen_test.dart`, `test/account_test.dart`. **Pas encore essayé sur un appareil.**
- **Connexion TV par code** (`features/auth/device_login.dart`, API : `vixeo_backend/docs/connexion-tv.md`) :
  sur grand écran, la page de connexion affiche `TvCodeCard` : **le code court seulement, aucun
  QR code nulle part** (demande du développeur, 20/11/2026 ; ne pas en réintroduire ; l'API ne
  renvoie plus de lien `verification_url*` ; code lu caractère par caractère par les lecteurs
  d'écran) et la marche à
  suivre (« Paramètres » → « Connecter une TV » dans l'appli du téléphone) ; elle interroge
  `/auth/device/token` toutes les `interval` secondes et demande un nouveau code sur un 410. Le
  téléphone (ou un PC Windows) valide sur `/tv` en tapant le code. Le `device_code` reste en
  mémoire, jamais dans une URL.
- **TV en direct masquée pour l'instant** (demande du développeur, 17/11/2026) : `liveTvProvider`
  (`core/features.dart`, faux par défaut ; `--dart-define=LIVE_TV=true` la réaffiche) retire
  l'onglet et l'entrée du rail « Chaînes TV », le type et la section « Chaînes TV » de la
  recherche (aucune chaîne demandée), « Chaînes TV » de « À voir » et la tuile « Catégories des
  chaînes TV » des paramètres ; `/chaines-tv…`, `/chaine/:id` et `/profil/rangees/chaines-tv`
  mènent à l'accueil (`liveTvOnly`, `router.dart`). Le code et l'API de la TV restent ; les tests
  des chaînes la réaffichent avec `liveTvProvider.overrideWithValue(true)`.
- **TV en direct** (`features/tv`, API : `vixeo_backend/docs/tv-direct.md`) : **pas de page « TV »
  ni d'onglet** (supprimés, demande du développeur). Les
  chaînes sont sur l'accueil (**quatre rangées** « Chaînes TV généralistes », « … sport »,
  « … info », « … enfants », demande du développeur : `channelSections` classe les chaînes selon le
  nom de leur catégorie, mots-clés sans accents, 24 par rangée, rangée vide masquée ; aucune
  correspondance → une seule rangée « Chaînes TV » ; `ChannelRow` **sans « Voir tout »** ; test
  `test/home_channels_test.dart`) et dans la recherche
  (type « Chaînes TV » : grille `ChannelSearchResults`, filtre « Catégorie » de `/tv/categories`,
  même bouton `FilterChipButton` que « Genre » ; section « Chaînes TV » de « Tout »). Une chaîne
  passe toujours par `ChannelTile` (focus télécommande). **Logo** : l'URL `logo` de l'API, sur notre
  domaine (`/tv/logo/{hash}` : l'API relaie l'image du fournisseur sans la stocker, gardée 7 jours
  par l'appli) ; `http://` passé en `https://` par
  `TvChannel.fromJson` ; sans logo, une icône ; **toucher une chaîne ouvre sa page**
  (`ChannelScreen`, `/chaine/:id`, `openChannel`, demande du développeur ; comme une fiche film /
  série) : logo, nom, catégorie,
  « EN DIRECT », « Regarder » (focus à l'arrivée), « En ce moment » (titre,
  heures, barre de progression, résumé) et le **programme** (EPG, `/tv/channels/{id}/epg`,
  `tvGuideProvider` ; heures locales, « Demain 08:30 » ; un appui montre le résumé complet ; mis à
  jour toutes les 30 s ; sans guide sur le serveur : « Le programme n’est pas disponible pour le
  moment. »). Test : `test/channel_screen_test.dart`. « Regarder »
  ouvre tout de suite `PlayerScreen.live` **en plein écran, sur le `Navigator` racine** (`playLiveChannel`,
  `rootNavigator: true` : ni rail ni barre d'onglets par-dessus), qui demande son flux (`/tv/channels/{id}/stream`) sous
  le même indicateur que le début de la lecture (un seul chargement, pas de fenêtre avant). Lecteur : le même que pour
  les films et séries (`features/playback/player_screen.dart`, `LivePlayerScreen` n'en est qu'une entrée) ;
  boutons ronds `VxIconAction` / `VxFocusable` avec un libellé pour les lecteurs d'écran (les tests les cherchent par
  ce libellé : pas d'`IconButton` à infobulle). Contrôles en surimpression (retour, nom de la chaîne, « EN DIRECT » ; lecture / pause, son et
  volume (souris), « Revenir au direct », plein écran sauf
  sur TV : `fullscreen/`) ; le lecteur est **toujours horizontal** (`lockLandscape` à
  l'ouverture, `unlockOrientation` à la fermeture ; rien à verrouiller sur Windows), masqués après 4 s de lecture, rappelés par un appui, la souris ou une
  touche (la première touche de la télécommande ne fait que les montrer) ; raccourcis K, M, F et
  touches média. **Un seul flux par chaîne** (`url`), pas de choix de source ni de passage
  à une autre source (demande du développeur). Un flux qui refuse de démarrer, ou dont l'image ne
  bouge pas pendant 15 s (`stallTimeout`), affiche « Impossible de lire cette chaîne. » (ou la
  phrase de la cause quand le moteur la connaît) et « Réessayer » (une seule fois par échec). Un
  flux peut « jouer » avec un écran noir sans que le moteur le signale : le lecteur lit donc la
  position réelle (`engine.position`, pas `value.position`, figée pour un direct) ;
  tant que l'image ne bouge pas, les contrôles et un indicateur restent affichés. Test : `test/live_player_test.dart`. L'API renvoie une URL sur **notre
  propre origine** (un proxy signé, jamais l'adresse du fournisseur) ; `TvStream.headers` reste
  vide et est tout de même transmis au lecteur.
- **Lecteur : un écran, plusieurs moteurs** (demande du développeur ; détails et matrice de tests :
  [`docs/lecteur.md`](docs/lecteur.md)) : `PlayerScreen` et ses commandes sont les mêmes partout
  et ne parlent qu'à un `PlayerEngine` (`features/playback/engine/`, obtenu par
  `playerEngineFactoryProvider`, choisi par `engine_factory_io.dart`). Android / iOS :
  `NativePlayerEngine` (`better_native_video_player`, ExoPlayer / AVPlayer). **Windows :
  `MediaKitPlayerEngine`** (`media_kit` + `media_kit_libs_windows_video`, libmpv : HLS, MP4,
  MPEG-TS, en-têtes HTTP de la source ; `MediaKit.ensureInitialized()` dans `main.dart`).
  Autres (tests) : `VideoPlayerEngine` (`video_player`). Ne jamais importer un plugin vidéo dans
  `PlayerScreen` : passer par le moteur. Erreurs : `PlayerError(kind)` (réseau, format, DRM) →
  une phrase par cause (`playerErrorMessage`). Sous-titres : WebVTT lu par `webvtt.dart`, dessiné
  par Flutter (même rendu partout). **DRM : pas implémenté** (un flux protégé est refusé avec une
  phrase) ; aucune clé dans Flutter. Tests : `test/player_engine_test.dart` (faux moteur) ; les
  appareils se testent à la main (matrice de `docs/lecteur.md`).
- **Commandes du lecteur** (demande du développeur, d'après un autre lecteur ; `docs/lecteur.md`) :
  retour **en haut à gauche** (`VxBackButton`, comme les autres pages), « EN DIRECT » en haut à
  droite (chaîne qui joue) ; au milieu −10 s, lecture / pause (cercle de chargement à sa place),
  +10 s (J / L), toujours blancs (lecture ouvre les sources tant qu'aucune n'est choisie) ; en bas
  à gauche le titre, l'année ou l'épisode et « Via » la source, la barre de progression (toujours
  là pour un titre, à 0 avant la vidéo), puis les icônes (blanches, sans fond, petites ; curseur
  de volume seulement avec une souris, pas sur Android / iOS) et le temps à droite. **Pas de
  flèche** : trop d'icônes pour la largeur, la rangée **défile de gauche à droite**. **Pas de
  lecteur externe** (supprimé, demande du développeur). **Cadrage** (Ajuster / Remplir / Zoom,
  `VideoFit`, `_FramedVideo` : la vue posée à la forme de l'image, `PlayerEngineValue.aspectRatio`,
  puis agrandie par `FittedBox` ; même arbre, la vue native n'est jamais reconstruite). Tests :
  `test/player_engine_test.dart`.
- **Profil unique du compte** : chaque compte possède exactement un profil, créé à l'inscription
  et résolu automatiquement par l'API depuis l'utilisateur authentifié. Il n'existe plus de page
  « Qui regarde ? », de sélection, d'ajout, de changement ou de suppression de profil, de PIN,
  de profil enfant, de contrôle parental ni de restriction d'âge. L'ancien en-tête
  `X-Profile-Id` n'est plus envoyé ni interprété. Le backend conserve un seul profil par compte
  (migration : conservation du plus ancien, suppression des doublons et de leurs données), impose
  une contrainte unique sur `profiles.user_id`, retire les colonnes de restriction et expose
  uniquement GET/POST /profiles et GET/PATCH /profiles/{id}. POST ne sert qu'à créer le profil
  initial d'un compte qui n'en aurait pas encore ; aucun endpoint de suppression ou de PIN.
  L'édition se fait depuis le menu « ⋮ » de la page « Profil » : nom, pseudo, biographie, réseaux,
  confidentialité, avatar, photo et couverture. Les préférences de lecture, la bibliothèque,
  les avis, les listes et les messages restent attachés à ce profil unique.
  Tests : `test/profile_screen_test.dart`, tests de session et de modèles.
- **Mises à jour** (`features/updates`, API : `vixeo_backend/docs/mise-a-jour.md`) : sur Android,
  Windows et iOS, `UpdateGate` (dans le `builder` de `MaterialApp.router`) interroge `GET /app/update` avec le
  **build** installé (`package_info_plus`) au lancement et au retour au premier plan (toutes les 6 h
  au plus). `update_required` → écran « Mise à jour nécessaire » à la place de l'appli ;
  `update_available` → barre `UpdateBanner` tout en haut des pages (« Une nouvelle mise à jour est
  disponible », bouton « Télécharger » à droite ; elle prend la marge de la barre d'état, les pages
  sont dessous). Pas de fenêtre ni de page « Mise à jour » dans les paramètres (demande du
  développeur). Une vérification qui échoue ne bloque jamais. Sur Android (pas de Play Store),
  « Télécharger » (barre) et « Mettre à jour » (écran bloquant, `UpdateButton`) téléchargent l'APK
  (`latest.download_url`, https uniquement, sans le jeton Vixeo), vérifient son SHA-256, puis
  ouvrent l'installateur d'Android (`ApkInstaller`, canal `app.vixeo/updates` dans `MainActivity.kt`,
  `FileProvider` sur `cache/updates`, permission `REQUEST_INSTALL_PACKAGES`), qui demande une
  confirmation ; la progression est partagée (`updateDownloadProvider`). **Sur Windows**, les
  mêmes boutons téléchargent l'installateur (`vixeo-setup-<build>.exe`), vérifient son SHA-256,
  le lancent en silencieux (`/SILENT /SUPPRESSMSGBOXES /NORESTART`, détaché) et ferment Vixeo,
  que l'installateur relance (« Installation de la nouvelle version : Vixeo se ferme, puis
  redémarre. »). Sans fichier, ou sur iOS, le bouton ouvre la page d'installation du site.
  L'appli ne charge ni n'exécute de code tiers téléchargé. Publication :
  `docs/android-release.md`, `docs/windows-release.md`. Pour essayer les écrans d'une autre
  plateforme : version « profile » avec `--dart-define=UPDATE_PLATFORM=android`.
- **Version et signature** : `version: x.y.z+build` dans `pubspec.yaml` (`x.y.z` : version
  affichée). Les APK de la CI prennent comme build le numéro du run **+ 400** (`BUILD_OFFSET` de `build.yml` :
  le renommage du workflow, le 20/11/2026, a remis son compteur à 1 alors que le dernier APK était
  le build 367 ; ne jamais baisser ce décalage) (`--build-number`), toujours
  croissant ; un APK compilé à la main doit avoir un build plus grand que le dernier publié. La version Release est signée avec la clé de release
  (`android/key.properties` ou variables `VIXEO_KEYSTORE_*`, jamais dans le dépôt) ; sans clé, le
  build Release échoue. La CI publie chaque APK en release GitHub `android-<build>` (APK et
  SHA-256) et l'installateur Windows en release `windows-<build>` (même build ; `.exe` et
  SHA-256), **seule source** des mises à jour pour l'API (plus de commande `vixeo:release`) ;
  `[obligatoire]` dans le titre d'une release impose la mise à jour à sa plateforme. Pas d'appli
  iOS pour l'instant (l'API répond « à jour » pour iOS). Détails : `docs/android-release.md`,
  `docs/windows-release.md`. **Fenêtre Windows** (`main.dart`, `_setUpWindows`, `window_manager`) :
  titre « Vixeo », 1280×800, 960×600 au minimum, centrée, fond de la charte ; icône
  `windows/runner/resources/app_icon.ico` (tirée de `brand/icons/icon-rounded.svg`).
- **Chargement au démarrage** (demande du développeur : un seul chargement) : un seul
  chargement : `AppLoading` (`core/widgets/app_loading.dart`, logo + cercle), affiché par
  l'écran de démarrage (`/demarrage`), pendant que la session et le profil unique se chargent et par
  `AppShell` au premier chargement de l'accueil (sans la navigation, une seule fois par lancement).
  La carte TV de la connexion montre une forme vide, pas de cercle, en attendant son code. Ne pas
  ajouter d'autre indicateur au démarrage. Test : `test/app_loading_test.dart`.
- **Mon compte** (`/profil/compte`, `AccountScreen`, « Paramètres » → « Compte » ; API :
  `vixeo_backend/docs/compte.md`) : « Adresse e-mail » (une phrase, **pas l'adresse sur la page**,
  demande du développeur ; « Modifier l'adresse e-mail » : l'adresse actuelle en lecture seule,
  nouvelle adresse + mot de passe, `POST /me/email`, la session garde la nouvelle adresse,
  `SessionController.updateUser`), « Mot de passe » (« Changer le mot de passe » : actuel +
  nouveau, `POST /me/password`, les autres appareils sont déconnectés), « Vos données »,
  « Supprimer le compte ». Les champs de mot de passe passent par `PasswordField` (œil). Test :
  `test/account_test.dart`.
- **Inscription et mot de passe** (demande du développeur) : pas de texte d'aide sous les champs
  (ni « Unique sur Vixeo · 3 à 30 caractères », ni « 8 caractères minimum ») ; les règles
  n'apparaissent qu'en message d'erreur. Chaque champ de mot de passe a l'œil « Afficher / Masquer
  le mot de passe » (connexion, inscription, mot de passe oublié).
- **Polices** : Sora et Inter sont dans `assets/fonts` (licence OFL) ; rien n'est téléchargé au
  lancement (pas de `google_fonts`).
- **API** : passer par `ApiClient` (jeton Bearer ajouté automatiquement, sans en-tête de profil,
  erreurs → `ApiException` avec le message français de l'API, 401 → session expirée).
- **Modèles** : écrits à la main d'après `vixeo_backend/docs/openapi.json` (seuls les champs
  utilisés). À chaque changement de l'API, mettre à jour le modèle et son test
  (`test/models_test.dart`). Piste à valider : générer le client depuis la spec.
- **Synchro** : ne jamais appeler `/profiles/{id}/sync` ailleurs que dans `LibraryController`
  (`features/library/library.dart`), qui suit `vixeo_backend/docs/synchronisation.md`.
- **TV / télécommande** :
  - tout élément sélectionnable passe par `VxFocusable` (anneau de focus vert, blanc sur un
    élément vert, léger zoom ; appui long ou touche menu = menu contextuel) ;
  - chaque écran donne le focus à un élément à l'arrivée (`autofocus: true` sur un seul élément) ;
    `VxFocusable` ne vole jamais le focus à un élément du même écran ou de la même fenêtre (champ
    de texte…), mais une fenêtre (choix, confirmation) le prend même si la page dessous l'avait ;
  - barre de mise à jour : flèche Haut en haut d'une page (rien au-dessus) → bouton « Télécharger »,
    flèche Bas → retour à l'élément de la page ; jamais depuis une fenêtre ou un menu ;
  - seul ce qui se presse prend le focus (`VxFocusable` sans `onPressed` ni `onLongPress` : non
    focalisable ; `InfoSection` est du texte simple) ;
  - touche Retour (`BackNavigationGuard`) : d'une sous-page vers l'accueil (ou vers la page
    d'accueil de la connexion depuis `/connexion/email`, et vers `/connexion/email` depuis
    l'inscription et le mot de passe oublié) ; depuis l'accueil, la connexion ou
    confirmation avant de quitter l'appli depuis l'accueil ou la connexion ; sur TV, Retour pendant la saisie
    d'un champ de texte ne fait que quitter le champ (ce qui ferme le clavier), sans changer de
    page (`BackNavigationGuard.leaveTextField`) ;
  - **navigation au D-pad** (`core/widgets/focus_navigation.dart`, demande du développeur,
    21/11/2026) : `RemoteNavigation` (dans le `builder` de `MaterialApp.router`) pose **une seule
    règle de parcours** pour toute l'appli (`vxTraversalPolicy` : tout `FocusTraversalGroup` la
    reçoit, `policy: vxTraversalPolicy`, ne jamais en créer un sans) : Bas puis Haut revient sur la
    même carte d'une rangée à l'autre, et le déplacement du focus ne fait pas défiler lui-même.
    Sur TV, `RemoteNavigation` fait défiler **une fois, en douceur**, jusqu'à l'élément qui a le
    focus (tout élément, pas seulement `VxFocusable` ; un peu au-dessus du milieu de chaque liste,
    `RemoteNavigation.alignment`) : plus de saut suivi d'une animation. Touche maintenue
    (`RemoteKeys.repeating`) : défilement plus court, et la grande image attend que le focus
    s'arrête (`RepeatSettler` dans `HeroSelection`) au lieu de charger l'image de chaque carte
    traversée. Haut / Bas sortent d'un **champ d'une ligne** (Flutter y déplaçait le curseur et
    gardait le focus) ; Gauche / Droite y déplacent le curseur ; dans un champ de plusieurs lignes,
    Haut / Bas changent de ligne ;
  - **rail et pages** (`_LargeShell`, `shell/app_shell.dart`) : le rail et la page sont deux
    `FocusScope` ; Gauche au bord gauche d'une page → la destination **affichée** du rail (pas
    l'icône à la même hauteur) ; Droite depuis le rail → l'élément de la page qui avait le focus
    (sinon le premier) ; Haut / Bas ne passent jamais du rail à la page ni l'inverse ; un bord que
    le rail ou la page ne gère pas va à ce qui les entoure (`EdgeDirectionalFocusAction(outer:)` :
    Haut en haut d'une page → barre de mise à jour). Test : `test/dpad_test.dart` ;
  - les tailles TV sont celles du design 1920×1080, converties avec `Layout.of(context).tv(px)` ;
  - les rangées horizontales sont dans un `FocusTraversalGroup(policy: vxTraversalPolicy)` ;
  - accueil grand écran : la grande image et ses informations suivent la carte sélectionnée
    (focus : tout de suite) ou survolée à la souris (`onHovered`, après 150 ms), rangée
    « Continuer à regarder » comprise. Les titres de l'accueil et de la recherche arrivent avec
    leur résumé (`MediaItem.summary` : durée ou saisons, genres, âge conseillé) : tout s'affiche
    d'un coup (`TitleFacts`), sans requête de fiche. Seuls ceux de « Continuer à regarder » n'en ont
    pas : leur fiche (`titleProvider`) est lue quand la sélection reste 400 ms, et note, année,
    durée, âge et genres apparaissent ensemble (place réservée, rien ne bouge). À l'arrivée, la première
    carte de la première rangée (« Continuer à regarder » s'il y en a, sinon la première liste) a
    le focus et occupe la grande image : pas de « titre à la une » (`featured`) sur grand écran,
    ni de bouton « Plus d'infos » ; OK ou un clic sur la carte ouvre la fiche. Le carrousel du
    téléphone garde les titres à la une.
- **Rangées « légères » de l'accueil** (tendances du jour, plateformes, chaînes, studios,
  langues : l'API les donne sans logo ni `summary`) : `_HomeRow` (`home_screen.dart`) demande les
  titres qui n'en ont pas **en une requête par rangée** (`titlesByIdProvider`, API
  `/catalog/titles`), quand la rangée est construite (près de l’écran) ; les cartes ont alors leur
  note et la grande image (TV) son logo et son résumé tout d'un coup, comme les autres rangées. `MediaItem.withDetails`
  complète un titre. Test : `test/home_tv_test.dart`.
- **Transition entre les pages** (demande du développeur) : un **fondu enchaîné « fade
  through »** (300 ms, `vxPageFade`, `VxPageTransition` dans `core/theme.dart`), sans glissement :
  la page qui part s'efface d'abord (les premiers 40 %), puis la nouvelle apparaît (de 30 % à la
  fin) en grandissant un peu (96 % → 100 %). Les deux pages ne sont jamais visibles l'une sur
  l'autre (l'ancien fondu les superposait : effet « double image », peu naturel). Le retour a
  exactement le même rythme (courbes inverses dédiées, `reverseCurve`). Le thème le règle pour
  toutes les plateformes (`pageTransitionsTheme` → `VxFadePageTransitionsBuilder`) : toute route
  `builder:` de go_router et tout `MaterialPageRoute`. Les onglets passent par `tab(state, …)`
  dans `router.dart`, qui renvoie une **`MaterialPage`** : une `MaterialPageRoute` n'anime sa
  sortie que sous une autre `MaterialPageRoute` (avec une `CustomTransitionPage`, la page
  quittée restait visible dessous). Ne pas ajouter d'autre transition. Test :
  `test/page_transition_test.dart`.
- **Page ou onglet vide** (demande du développeur, 23/11/2026 : le design du « Fil d'actualité »
  vide, en un seul composant) : toujours **`EmptyState`** (`core/widgets/common.dart` : icône,
  titre, phrase et bouton facultatif, centrés, tailles TV) : fil, « Notifications », onglets d'une
  page de profil, pages de listes… Ne pas écrire d'autre message de liste vide.
- **Rangées de l'accueil : « Voir tout »** (demande du développeur) : à droite du titre de chaque
  rangée, un bouton rond à flèche (`SectionHeader(onSeeAll:)`) ouvre la liste entière
  (`TitleListScreen`, `catalog/list_screen.dart`, `/liste/:type/:list?titre=…`) : bouton retour,
  titre de la rangée, grille qui charge la page suivante en arrivant à la fin (`PagedGrid`, le
  même que la recherche ; API `/catalog/{type}/lists/{list}`, `titleListProvider`).
- **« Voir tout » de la fiche et de la page d'une personne** (demande du développeur,
  20/11/2026) : le même bouton rond sur « Vous pourriez aussi aimer »
  (`RecommendationsScreen`, `/titre/:type/:id/recommandations`, paginé,
  `recommendationsProvider`), « Distribution » et « Équipe technique » (`CreditsScreen`,
  `/titre/:type/:id/distribution` et `/equipe`, grille de `PersonCard`), « Connu pour » et
  « Filmographie » (`PersonTitlesScreen`, `/personne/:id/connu-pour` et `/filmographie`, tous les
  titres, `personCreditsProvider`). Mêmes pages que « Voir tout » de l'accueil (`_SeeAllPage` :
  retour, titre, grille `PagedGrid` : **20 d'abord, les suivants en défilant**, voir « Pages de
  20 »). **La filmographie est une rangée horizontale** comme les autres (`PosterRow`, les 20
  titres que donne la page d'une personne, plus de grille sur la page). Test :
  `test/see_all_test.dart`.
- **Pages de 20** (demande du développeur, 24/11/2026 : « éviter les trop grosses requêtes ») :
  **toute liste longue se lit 20 éléments à la fois**, la page suivante quand la fin approche en
  défilant (`catalog/paging.dart` : `pageSize`, un provider par page comme `PagedGrid`,
  `PagedBuilder` / `watchPages`, `PagedFooter` (cercle ou « Réessayer » sous la liste),
  `LoadMoreOnScroll` et `LoadMoreSentinel` pour une liste construite d'un coup ; jamais de bouton
  « Afficher plus ») : « Voir tout » du catalogue, distribution, titres d'une personne, pages d'un
  membre (« À voir », J'aime, vus, personnes, avis, abonnés, abonnements, listes), mes listes (et
  « Ajouter à une liste »), « Mes avis » (l'API filtre le type et trie, `myReviewsProvider`),
  notifications, activité d'un profil, fil, commentaires, messages. Mes « À voir », J'aime et vus
  viennent de la synchro (tous sur l'appareil) : leurs fiches (`/catalog/titles`) sont demandées
  **20 titres à la fois**, au fil du défilement. Une recherche, un filtre ou un tri que l'API ne
  fait pas lit toutes les pages, **l'une après l'autre** (20 par requête). Tests :
  `test/see_all_test.dart`, `test/profile_screen_test.dart`, `test/tmdb_test.dart`.
- **Page « Chaînes TV »** (`/chaines-tv`, `TvChannelsScreen` ; demande du développeur : comme
  l'accueil) : une **rangée par catégorie** (`channelCategorySections`, `tvChannelRowsProvider` :
  catégories et chaînes demandées une fois, 24 chaînes par rangée, catégorie vide masquée), avec
  le bouton rond « Voir tout » qui ouvre toute la catégorie (`TvCategoryScreen`,
  `/chaines-tv/categorie/:id?titre=…` : bouton retour, nom de la catégorie, grille
  `ChannelSearchResults`). **Ni champ de recherche ni filtre de catégorie sur cette page**
  (supprimés, demande du développeur) : on cherche une chaîne dans la recherche. Toutes les
  catégories qui ont des chaînes ont leur rangée.
- **Rangées à trier et masquer** (demande du développeur) : « Paramètres » → « Rangées de
  l’accueil » (`/profil/rangees/accueil`) et « Catégories des chaînes TV »
  (`/profil/rangees/chaines-tv`), même page `RowsSettingsScreen` : chaque rangée a « monter »,
  « descendre » (des boutons, pas de glisser-déposer : ils marchent à la télécommande) et
  « afficher / masquer », plus « Réinitialiser ». Réglage `RowPreferences` (ordre + rangées
  masquées, par clé : `Section.key` pour l'accueil, id de catégorie pour les chaînes), **gardé sur
  l'appareil, par profil** (`row_preferences.dart`, stockage protégé `vixeo.rows.<page>.<profil>` ;
  pas synchronisé : il faudrait un champ de profil côté API). Une rangée jamais placée (nouvelle
  liste, nouvelle catégorie) vient après les autres, affichée. Appliqué par `HomeScreen` et
  `TvChannelsScreen` (`visible`). « Continuer à regarder » et le carrousel ne sont pas concernés.
  Test : `test/row_preferences_test.dart`.
- **Page « Notifications »** (`/notifications`, `InboxScreen`, `features/notifications/inbox_screen.dart`
  et `inbox.dart` ; demande du développeur, 21/11/2026 ; API : `vixeo_backend/docs/social.md`) :
  **plus dans la navigation** (demande du développeur, 25/11/2026 : ni onglet ni rail) : une
  **cloche en haut à droite de la page « Profil », juste avant « ⋮ »** (`ProfileScreen`,
  toutes les tailles d'écran ; uniquement si le compte possède un pseudo : `socialAvailable`, la route
  mène alors à l'accueil), avec une **pastille** du nombre de non lues (`NavigationBadge`, « 9+ »
  au-delà ; lue « Notifications, 3 notifications non lues ») ; la page a son bouton retour. Pastille : `unreadNotificationsProvider` (`GET /notifications/count`),
  relue à l'arrivée de la navigation, à chaque changement de page (30 s au plus entre deux,
  `_UnreadWatcher` d'`AppShell`), au retour au premier plan et à l'arrivée d'un push du canal
  `social` ; **pas de minuterie**. La page : **tout dans une seule liste, sans sections** (demande
  du développeur, 23/11/2026 : ne pas séparer activité et prochains épisodes) : d'abord les
  demandes d'abonnement (compte privé : `AccountTile`, « Accepter » ✓ et « Refuser » ✕,
  `followRequestsProvider`), puis les prochains épisodes des séries « À voir » (le plus proche
  d'abord ; `_EpisodeTile` : image, série, « Saison 2, épisode 5 · Titre », « Demain à 21:00 » en
  vert ; `episodeCalendarProvider`, `GET /notifications/episodes`), puis ce qui s'est passé, le plus
  récent d'abord : l'activité des membres (`activityFeedProvider`, 20 par page, chargées en défilant :
  avatar, « **Max** vous suit. », « … aime votre avis sur Dune. », « il y a 5 min », point vert tant
  que non lue ; les demandes n'y sont pas une deuxième fois) mêlée aux épisodes sortis cette
  semaine (« Sorti hier »). Rien : l'`EmptyState` du « Fil d'actualité » (« Aucune
  notification »). Un appui ouvre la page du membre, mon avis (`ReviewScreen`) ou la série. **Ouvrir la page lit tout** (`POST /notifications/read`, après le
  premier chargement ; les points restent jusqu'à la visite suivante). Dates en français :
  `episodeWhen`, `timeAgo`, `dayLabel`. Test : `test/inbox_test.dart`.
- **Compte privé, réseaux sociaux, J'aime** (`features/social`, demande du développeur,
  21/11/2026, comme Twitter ; API : `vixeo_backend/docs/social.md`) : **« Biographie »** (160
  caractères au plus), **« Réseaux sociaux »** (un champ par réseau, `SocialNetwork` : Instagram, X,
  TikTok, YouTube, Letterboxd, Threads, Bluesky, site web ; le pseudo ou l'adresse, l'API garde le
  pseudo ; champ vidé = retiré) et **« Compte privé »** sont dans **« Modifier le profil »**
  (`ProfileEditorScreen`, « ⋮ » → « Modifier mon profil » de la page « Profil » ; demande du
  développeur, 25/11/2026 : plus de pages à part dans « Paramètres »), envoyés avec le reste par
  `PUT /profiles/{id}` (`bio`, `social_links`, `is_private`). En-tête du profil (`ProfileHeader`) : cadenas
  après le nom d'un compte privé, puis les réseaux sous la biographie (`SocialLinkChip` : icône et
  « @pseudo », ouvre la page dans le navigateur ; sur TV, affichés seulement). Page d'un membre
  privé qu'on ne suit pas (`can_view` faux) : en-tête et compteurs seulement, carte « Ce compte est
  privé », abonnés / abonnements non cliquables, aucune liste demandée. Bouton (`_FollowButton`,
  `FollowStatus`) : « Suivre » → abonné tout de suite (compte public) ou **demande** (« Demande
  d'abonnement envoyée à @max ») ; « Demande envoyée » (un appui la retire) ; « Ne plus suivre »
  (confirmation pour un compte privé). **J'aime** : cœur à droite de l'avis d'un autre membre
  (`ReviewLikeButton`, `reviewLikesProvider` : affiché tout de suite, gardé par id d'avis, remis
  en cas d'échec ; invité : « Connectez-vous… »), avec le nombre ; mes avis montrent leur nombre
  de J'aime (pas de cœur). Push : réglage « Activité » (`SocialAlertsSetting`, activé par défaut,
  par profil sur l'appareil, `social` de `PUT /push/device`), canal Android `social`. Tests :
  `test/profile_screen_test.dart`, `test/notifications_test.dart`, `test/inbox_test.dart`.
- **Notifications** (`features/notifications`, « Paramètres » → « Notifications »,
  `/profil/notifications` ; API : `vixeo_backend/docs/notifications.md` ; demande du développeur :
  **un serveur de push**, l'appli ne programme rien) : **Firebase Cloud Messaging**
  (`firebase_messaging`, `PushMessaging` / `FirebasePushMessaging`). Firebase est configuré par
  les ressources Android écrites au build depuis les secrets `FIREBASE_*` (`build.gradle.kts`,
  `docs/android-release.md` § 6 ; **pas de `google-services.json`** dans le dépôt ; il faut les
  quatre, la CI nomme ceux qui manquent) ; sans eux, pas de jeton : la page dit « Cette version de
  l'appli ne reçoit pas encore les notifications… » ; serveur sans `FCM_CREDENTIALS` : « Le
  serveur n'envoie pas encore de notifications. ».
  **Identifiant d'installation Firebase** (FID, firebase_messaging 17, le 23/11/2026 : `getToken` /
  `onTokenRefresh` dépréciés et retirés) : `FirebasePushMessaging.installationId()` écoute
  `onRegistered` **avant** d'appeler `register()` (la réponse arrive par ce flux, comme chaque
  changement : `installationIdChanges` → inscription forcée) ; Android a besoin du meta-data
  `firebase_messaging_installation_id_enabled` du manifeste ; le serveur envoie avec
  `message.fid`. **Pas encore essayé sur un appareil.**
  `PushRegistration` donne le FID à l'API (`PUT /push/device` : `fid`, profil actif, réglages
  « Nouveaux épisodes » et « Activité », `utc_offset`) au lancement, au retour au premier plan (6 h
  au plus entre deux envois identiques), quand la session, le profil, un réglage ou le FID change
  (`NotificationsGate`, dans le `builder` de `MaterialApp.router`, sous `UpdateGate`) ; la
  déconnexion supprime l'inscription côté serveur. Réglage « Nouveaux épisodes » par profil **sur
  l'appareil** (`EpisodeAlertsSetting`, `LocalStore`, désactivé par défaut) ; l'activer pose la
  question du système (Android 13+) ; refusé : carte « Notifications bloquées » et « Ouvrir les
  réglages ». « Envoyer une notification de test » : le serveur l'envoie
  (`POST /push/device/test`). **Pas de liste des prochaines alertes** (demande du développeur).
  Une notification reçue appli ouverte est affichée par l'appli (`flutter_local_notifications`,
  `SystemNotifications`, canaux Android `episodes` et `general` créés au lancement) ; un appui
  ouvre `data.path` (aussi quand la notification lance l'appli). Icône
  `drawable/ic_notification.xml` (gardée par `raw/keep.xml`), couleur `values/colors.xml`,
  désucrage Java activé (`build.gradle.kts`). **Windows (pas de FCM) : canal temps réel**
  (demande du développeur, 23/11/2026) : `PushTransport` (`pushTransportProvider` : `firebase`,
  `realtime` sur Windows avec une clé Reverb, sinon `none` → une phrase) ; l'appli s'inscrit avec
  `platform: windows` sans FID, garde l'`id` de la réponse (`pushDeviceProvider`) et écoute
  `private-push-devices.{id}` (`realtimeNotificationsProvider`, ouvert tant que l'appli tourne) ;
  chaque événement `notification` (`PushNotification.fromRealtime`) est affiché comme un push reçu
  appli ouverte (notification Windows : `PluginNotifications`, AppUserModelID `Vixeo.Vixeo`,
  icône `assets/images/app_icon.png` ; un clic ramène la fenêtre devant) ; la page dit « Sur
  Windows, les notifications arrivent tant que Vixeo est ouvert. ». Rien appli fermée (pas de
  MSIX). Les tests passent par `FakePush`, `FakeNotifications` et `FakeSocket`
  (`test/notifications_test.dart`, `test/realtime_fakes.dart`).
- **Plug-ins façon Nuvio** : supprimés le 27/11/2026 (page, dépôts, moteur JavaScript, sandbox, exécution et tests). Ne pas les réintroduire. Le catalogue TMDb et les chaînes TV intégrées sont indépendants.

- **Messagerie** (`features/messages`, le développeur, 22/11/2026, comme Instagram ; API :
  `vixeo_backend/docs/messagerie.md`) : **une entrée à part de la navigation** (demande du
  développeur, 23/11/2026 : pas dans le « Fil d'actualité »), onglet du téléphone et entrée du rail
  **« Messages »** après « Recherche » (`ConversationsScreen`, `/messages` ; uniquement si le compte possède un pseudo :
  `socialAvailable`, la route mène à l'accueil) : `VxPageHeader` avec « Écrire à un membre… »
  (recherche des comptes, `MemberSearchResults`) et « Créer un groupe » (`VxIconAction`), les
  **demandes reçues** (« Accepter » ✓ / « Refuser » ✕) puis les conversations (avatar ou icône du
  groupe, « Vous : … », date, pastille des non lus). **Pastille de la navigation** sur « Messages »
  (onglet et rail, comme « Notifications » : `NavigationBadge`, « 9+ » au-delà de 9, lue
  « Messages, 12 messages non lus ») : `unreadMessagesProvider` (`GET /messages/count` : messages
  des autres non lus dans toutes les conversations, demandes reçues comprises), relue avec celle
  des notifications (`_UnreadWatcher` : arrivée de la navigation, changement de page à 30 s au
  plus, retour au premier plan), à l'arrivée d'un push du canal `social`, après la lecture d'une
  conversation et le refus d'une demande ; pas de minuterie. Une conversation (`ConversationScreen`,
  `/messages/:id`, sans la barre d'onglets) : en-tête (retour, nom : la page du membre ou
  « Gérer le groupe », focus à l'arrivée ; options : « Voir le profil », « Bloquer » /
  « Débloquer »), messages (liste inversée, les plus anciens chargés en remontant, jour au-dessus
  du premier message d'un jour, nom de l'expéditeur dans un groupe, mes bulles à droite en vert à
  16 %, ✓ / ✓✓ lu), photo (téléchargée avec le jeton, `attachmentBytesProvider`, gardée 5 min ;
  un appui l'ouvre en plein écran) ou vidéo (icône et taille) ; **appui long ou touche menu** sur un
  message : « Copier le texte », « Supprimer pour tout le monde » (le mien) ; en bas, le champ,
  le trombone (photo / vidéo, `file_picker`, 100 Mo au plus ; pas avant l'acceptation d'une
  demande) et « Envoyer » ; une demande reçue : « Accepter » / « Refuser » à la place. Groupes :
  `NewGroupScreen` (`/messages/nouveau-groupe` : nom, membres cherchés et choisis) et
  `GroupSettingsScreen` (`/messages/:id/groupe`, `InfoPage` : nom, membres, transmettre
  l'administration, retirer, ajouter, « Quitter le groupe »). Page d'un membre : bouton rond
  « Envoyer un message » à côté du bouton principal (`ProfileHeader(onMessage:)`). État :
  `ConversationController` (`conversationProvider(id)`, relu à chaque changement annoncé, messages
  marqués lus quand ils s'affichent), `inboxProvider` (invalidé après une lecture, un envoi, une
  réponse). **Temps réel : `Realtime`** (`core/api/realtime.dart`, `realtimeProvider` de
  `auth/session.dart`, un par session et profil) : **une seule** WebSocket vers Laravel Reverb
  (protocole Pusher, `REVERB_*` de `--dart-define`, variables de la CI), ouverte tant qu'un canal
  est écouté, un canal privé par sujet (`events(canal)`, autorisé par
  `ApiClient.authorizeBroadcasting`) : une conversation affichée (`conversationChannel(id)` =
  `private-messages.{id}`) ou les notifications de Windows (`private-push-devices.{id}`, voir
  « Notifications ») ; reconnexion (1 s, 2 s… 30 s) puis `resync` ; sans clé Reverb, rien ne
  s'ouvre (la page relit la conversation après chaque action). Dates de l'API en ISO 8601 avec fuseau, affichées en heure
  locale. Confirmations : `showVxConfirm` (`core/widgets/choice.dart`). Test : `test/messages_test.dart`.
- **Réseau social des films et séries** (`features/network`, demande du développeur, 23/11/2026 :
  « comme Twitter mais sans tweet de texte » ; API : `vixeo_backend/docs/social.md`,
  `docs/moderation.md`) : **toute publication porte sur une œuvre** (avis, visionnage, J'aime,
  liste), la conversation est dans les commentaires.
  - **Navigation du téléphone** : Accueil · Fil d'actualité · Recherche · Messages · Profil (icônes
    seules ; « Notifications » (cloche) et « ⋮ » (dont « Paramètres ») en haut de la page « Profil »,
    boutons ronds ; le profil unique garde l'onglet « Paramètres »). Tablette et ordinateur : « Fil d'actualité » dans le rail,
    après « Chaînes TV ». **Pas de « Fil d'actualité » ni de « Messages » sur TV** (la TV sert à
    regarder ; ce qui aide à choisir est sur la fiche).
  - **« Fil d'actualité »** (renommé de « Fil » le 23/11/2026, demande du développeur ;
    `FeedScreen`, adresse `/fil`) : il montre **les avis, les titres vus, les J'aime et les listes**
    (demande du développeur, 23/11/2026) ; **deux onglets** (`VxTabs`, `core/widgets/tabs.dart`) :
    **« Pour toi », par défaut** (`feedProvider(FeedTab.forYou)`, `GET /social/feed/for-you?page=` :
    avis et listes de tout le réseau, titres vus et aimés des comptes suivis, classés par l'API) et
    **« Abonnements »** (`feedProvider(FeedTab.following)`, `GET /social/feed?before=` : avis
    (`ReviewPost`), listes (`ListPost`), titres vus et aimés regroupés (`TitlePost`, `FeedTitle` =
    `FeedWatched` / `FeedLiked` : « Léa et Max ont vu… », « Léa et Max aiment… ») des comptes
    suivis) ; la page suivante en arrivant à la fin ; « Comptes à suivre » (`SuggestionCard`,
    `GET /social/suggestions`, « 82 % de goûts en commun ») après le 3ᵉ élément, ou seuls quand
    l'onglet est vide. Pas de bouton « Messages » (il a son onglet).
  - **Avis** : un avis a sa page (`ReviewThreadScreen`, `/avis/:id`) avec ses **commentaires**
    (`CommentsSection` : « Contient des spoilers » `SpoilerSwitch`, « Publier » ; lus seulement
    sur TV) ; un avis ou un commentaire avec spoilers est caché derrière « Contient des spoilers ·
    Afficher » (`SpoilerText`), sauf pour son auteur ; la page de note a aussi
    « Contient des spoilers » (`MyRating.spoilers`, `contains_spoilers`). « Avis » sur la fiche :
    « Voir tout » → `TitleReviewsScreen` (`/titre/:type/:id/avis`, Populaires / Récents).
  - **Listes** (demande du développeur, 23/11/2026 : « À voir » et les listes fusionnées) :
    **« À voir »** (anciennement « À voir » : le groupe `favorite` de la synchro,
    `LibraryState.toWatch`) est **la première des listes**, **jamais supprimée**, sans titre ni
    description à choisir, triée par date d'ajout (`WatchlistCard`, `profile_sections.dart` ; page
    `MyListScreen`, **`/listes/a-voir`**, celle d'un membre `/membre/:username/a-voir` ; « À voir »
    des chaînes TV aussi). Les autres listes (`ListDetailsScreen`, `/listes/:id` ;
    `ListEditorScreen`, `/listes/nouvelle?item=movie:550`, `/listes/:id/modifier`) : **un titre et
    une description**, jusqu'à 100 titres **dans l'ordre choisi**, numérotés (idées : « Top 10 de
    2026 »… ; **plus de type « top 10 » / « liste »** : un « Top 10 » est une liste comme les
    autres), titres choisis par `pickTitle` et rangés avec « monter » / « descendre » / « retirer »
    (des boutons : télécommande) ; J'aime (`ListLikeButton`), commentaires.
  - **« Ajouter à une liste »** (demande du développeur, 23/11/2026 : choisir la liste) : le bouton
    marque-page d'un titre (`FavoriteButton`, fiche, grande image, appui long sur une carte :
    `addToList`) ouvre `showAddToList` : **« À voir » en tête** puis mes listes (une coche par liste
    qui a le titre, `GET /social/lists?item=`), et « Nouvelle liste » ; alertes « Ajouté à « À
    voir » », « Retiré de « Mon top » »… Sans listes à soi (pas encore de pseudo :
    `listsAvailable`), le bouton ajoute à « À voir » ou en retire directement. Fiche : aussi
    « Envoyer à un ami » (`recommendToFriend` : une conversation ou un membre, `share` de
    `POST /messages/{id}` ; la bulle montre la carte, `SharedCard`, un appui l'ouvre).
  - **Page de profil** (`ProfileView`) : **cinq onglets** (demande du développeur, 23/11/2026)
    **Activité · Listes · Avis · Aimés · Vus** (`ProfileTab`, `VxTabs`) ; **plus de « Journal »**
    (supprimé le 23/11/2026, ni page ni adresse). **Activité** (`ProfileActivitySection`,
    `activityProvider`, `GET /social/profiles/{pseudo}/activity`) : « la liste de tes actions avec
    la date » : avis, listes, titres vus et aimés sous leur jour (« Aujourd’hui », « Mercredi
    12 mars 2025 »), chacun avec son heure (`ActivityRow`), 20 par page en défilant. **Listes** :
    « À voir » puis les listes (`ProfileListsSection`, « Nouvelle liste »). **Avis** : les 10
    derniers. **Aimés** : grille des J'aime (`ProfileTitlesSection(grid: true)`) et personnes
    suivies. **Vus** : « Mon année 2026 » et grille des titres vus (`LibraryState.watched`, un
    membre : `socialWatchedProvider`, `GET /social/profiles/{pseudo}/watched` ; le bouton de l'année
    seulement s'il y a des titres vus). **Un onglet vide** montre l'`EmptyState` du « Fil
    d'actualité » (icône, titre, phrase ; demande du développeur, 23/11/2026). **Plus de « Mes 4
    favoris »** (supprimé le 23/11/2026, et `pinned_titles` côté API) ; un membre : « ⋮ » (liste
    déroulante `showVxMenu` : masquer du fil, bloquer, signaler : `showMemberMenu`) et « 82 % de goûts en commun »
    (`ProfileHeader(compatibility:)`).
    **Bilan de l'année** (`YearStatsScreen`, `/profil/bilan?annee=2026` : chiffres, mois, genres,
    mieux notés, série de l'année) ; **« Partager en image »** d'un avis, d'une liste ou de l'année
    (`StoryScreen`, format story 1080 × 1920 : feuille de partage d'Android, dossier
    Téléchargements sur Windows ; pas sur TV).
  - **Fiche** : `TitleSocialSection` (`GET /social/titles/{type}/{id}`) : abonnés qui l'ont vu,
    leur moyenne, avis populaires, listes qui l'ont ; rien pour un invité ou un titre sans activité.
  - **Note en fin de lecture** (demande du développeur, 23/11/2026) : dans les derniers 8 % d'un
    film ou d'un épisode (5 min au plus, `atTheEnd`), le lecteur marque le titre vu (film :
    « Vu » ; épisode : synchro `episode:…` et visionnage, `POST /profiles/{id}/diary`) puis, si le profil a gardé
    **« Proposer de noter à la fin »** (« Paramètres du profil » → « Après la lecture »,
    `rate_after_watching`, activé par défaut) et n'a pas encore noté le titre, une carte
    (`RateAfterWatchingCard`) : « Noter », « Plus tard » et le lien **« Désactiver dans les
    paramètres »**, qui remplace le lecteur par `/profil/parametres?reglage=noter`
    (`ProfilePreferencesScreen.rateAfterWatchingLocation` : le réglage a le focus). « Noter »
    remplace aussi le lecteur, par la page de note (retour : la fiche).
  - **Premier lancement** (`OnboardingScreen`, `/bienvenue`, ouvert après l'authentification quand
    `onboarded` est faux ; pas sur TV) : noter des titres connus, puis des comptes à suivre ;
    « Passer » à tout moment (`PUT /profiles/{id}` `onboarded: true`).
  - **Signaler, bloquer, masquer** partout (profil, avis, liste, commentaire, message : `report`,
    raisons de `GET /social/report-reasons`) ; « ⋮ » de la page « Profil » → **« Comptes bloqués et
    masqués »** (`HiddenAccountsScreen`, `/profil/comptes-masques` ; plus dans « Paramètres », demande
    du développeur, 25/11/2026). Notifications : `review_comment`,
    `list_like`, `list_comment`, `moderation` (« Modération »).
  - Mots d'une page de l'appli réservés côté API (`Usernames::RESERVED`) : `fil`, `listes`,
    `bienvenue`, `messages`, `description`, `journal`, `bilan`. Tests : `test/network_test.dart`,
    `test/profile_screen_test.dart`.
- **Résumé et biographie** (`DescriptionLink`, `catalog/description_screen.dart`) : sur la fiche et
  la page d'une personne, les 5 premières lignes puis, **seulement si le texte est plus long**,
  « Lire la suite », qui ouvre le texte entier sur une page à part (`DescriptionScreen`,
  `/description`, texte passé avec la route, jamais dans l'adresse ; `VxPageHeader(back:)` ; Haut /
  Bas de la télécommande font défiler le texte, Haut en haut revient à « Retour »). Test :
  `test/description_test.dart`.
- **Pas de page « Avancé »** (supprimée, demande du développeur, 25/11/2026 : ni `/profil/avance`,
  ni « Mémoriser le dernier profil », ni « Vider le cache ») : l'unique profil du compte est
  automatiquement restauré au lancement. Lignes des réglages communes :
  `profiles/settings_rows.dart` (`SettingsSection`, `SettingsChoiceRow`, `SettingsSwitchRow`,
  `SettingsActionRow`).
- **Rail de navigation sur un écran bas** : icônes et marges rétrécissent selon la hauteur
  (40 au minimum), puis le rail défile avec une barre (`_Rail`, `shell/app_shell.dart`). Test :
  `test/profile_features_test.dart`.
- **Pas de pages « Films » ni « Séries »** (supprimées, demande du développeur) : ni route, ni
  onglet, ni entrée du rail. `HomeScreen` et
  `homeProvider` n'ont plus de paramètre `type`. Pour ne voir que les films ou les séries : le
  filtre de type de la recherche. Ne pas les réintroduire.
- **« J'aime » ❤ et personnes suivies** (demande du développeur, 20/11/2026 ; **le cœur est un
  J'aime, pas des favoris**, précisé le 23/11/2026 : « J’aime » / « Je n’aime plus », « Ajouté à vos
  J’aime », « Mes J’aime », « Ses J’aime ») : groupes `liked` et `followed` de la synchro
  (`LibraryController.setLiked` / `setFollowed`, API : `vixeo_backend/docs/synchronisation.md`),
  indépendants de « À voir ». Cœur `LikedButton` sur la fiche (films, séries ; pas sur les
  épisodes ni les chaînes), après « Ajouter à une liste » ; un J'aime va au fil d'actualité des
  abonnés ; « Suivre » / « Ne plus suivre »
  (`FollowPersonButton`) sur la page d'une personne, sous son métier et ses dates (connecté avec
  un profil) ; une personne suivie = item `person:<id>` (`ProfileItem.person`,
  `LibraryState.followedPeople`). Alertes : « Ajouté à vos J’aime », « Retiré de vos J’aime »,
  « Vous suivez … », « Vous ne suivez plus … ». Page « Profil », onglet « Aimés » : « Mes J’aime »
  (grille d'affiches) et « Personnes suivies » (`ProfilePeopleSection`, photos rondes
  `PersonCard`) ; « Voir tout » : `/profil/social/aimes` (`MyListScreen(collection:
  TitleCollection.liked)`, recherche et filtres de « À voir ») et `/profil/social/personnes`
  (grille). Page d'un membre : « Ses J’aime » et « Personnes suivies » (`socialLikedProvider`,
  `socialPeopleProvider`, API `/social/profiles/{username}/liked` et `/people`). Tests : `test/profile_features_test.dart`,
  `test/profile_screen_test.dart`, `test/models_test.dart`.
- **Actions sur un titre** (Ajouter à une liste, J'aime ❤, Vu / non vu, Noter, Envoyer à un ami) : toujours le même bouton
  rond **icône seule** (`VxIconAction`, `FavoriteButton`, `LikedButton`, `WatchedButton`, `RateTitleButton`), sans
  texte visible (libellé pour les lecteurs d'écran uniquement). Le même bouton ajoute et retire
  (« Ajouter à une liste » : il ouvre le choix des listes, voir « Listes »).
  Chaque action se confirme par une alerte (`showVxSnack`) : « Ajouté à « À voir » », « Retiré
  de « À voir » », « Marqué comme vu », « Marqué comme non vu » (`features/library/actions.dart`),
  « Note enregistrée : 8/10 », « Note supprimée ». **Noter un film, une série ou un épisode le
  marque vu** (l'API le fait pour un nouvel avis, demande du développeur, 23/11/2026 ;
  `TmdbRatings` relit la bibliothèque juste après : « Vu » s'affiche tout de suite).
- **Avis** (`features/tmdb`, nom historique ; API : `vixeo_backend/docs/avis.md`) : tout profil
  connecté note, modifie et supprime ses avis (`canRateProvider` = connecté avec un profil),
  **gardés par Vixeo seulement**. **Plus de liaison d'un compte TMDb ni de synchronisation**
  (supprimées, demande du développeur, 20/11/2026 : ni page ni tuile « Connexions » ; ne pas les
  réintroduire).
  **Films, séries et épisodes** (avis d'épisodes supprimés le 20/11/2026 puis **rétablis le
  21/11/2026**, demande du développeur) : étoile `RateEpisodeButton` en haut à droite de chaque
  carte d'épisode (rond sombre, « Noter l’épisode 3 »), badge « Ma note : 8/10 » après
  « Épisode 3 » (`seasonRatingsProvider`, une requête par saison), filtre « Épisodes » de
  « Mes avis », adresse `/avis/tv/1399?saison=1&episode=2` (« Voir la série »). Bouton
  « Noter » sur la fiche (film, série). **Noter se fait sur une page, jamais dans une fenêtre**
  (demande du développeur, 23/11/2026) : **« Noter » / « Mon avis »** (`ReviewScreen`,
  `/avis/movie/550`, `editRating(context, target:, subject:)`, `RatingSubject` passé en `extra` :
  titre, ligne, image, note connue ; sans lui, la page demande la note, `myRatingProvider`, et
  le titre) : `RatingForm` (`tmdb/rating_form.dart` : 10 étoiles par demi-points ; télécommande :
  ← →, chiffres, OK ; **commentaire facultatif**, « Contient des spoilers »), « Enregistrer » et,
  noté, « Supprimer » (confirmation) ; la page se ferme en rendant `(note,)`, `(null,)` ou rien.
  Fiche, épisodes, fin de lecture, premier lancement et « Mes avis » l'ouvrent. La page ne parle
  pas de TMDb et le bouton s'appelle « Supprimer » (demande du développeur). **« Mes avis »** (`/avis`,
  `ReviewsScreen`, ouverte depuis la page « Profil » ; « Ses avis » pour un membre,
  `ReviewsScreen(username:)`) : en-tête commun avec recherche (titre, commentaire, sans
  accents ni casse) et, comme la recherche (demande du développeur), filtres Tout (par défaut) /
  Films / Séries, « Années », « Note » (note de l'avis ; tous deux au curseur à deux poignées) et « Tri » (`ReviewSort` : plus
  récents par défaut, plus anciens, meilleures / moins bonnes notes, titre), « Réinitialiser ». Chaque avis montre ses étoiles (`StarRow`) et **aucun bouton** (demande
  du développeur) : un appui ouvre « Mon avis » (`ReviewScreen`, `/avis/movie/550`,
  `/avis/tv/1399`), où l'on change les étoiles et le commentaire (`RatingForm`,
  la même page que « Noter », `RatingSubject.of(item)`) ; « Enregistrer » et « Supprimer »
  (confirmation) ramènent à la liste, « Voir la fiche » ouvre le titre. Les avis arrivent 20 par
  20 en défilant (`myReviewsProvider` : type et tri par l'API ; recherche, années, note et tri par
  titre : toutes les pages, l'une après l'autre). Toute écriture passe par `TmdbRatings`, qui
  rafraîchit la fiche et « Avis ». Les notes vont de 0,5 à 10.
- **Notes des titres : IMDb, sinon TMDb** (`features/ratings`, demande du développeur,
  21/11/2026 ; API : `vixeo_backend/docs/notes.md`). **Plus de « Source des notes »** (supprimé le
  21/11/2026 : réglage `rating_source`, `RatingSource`, `RatingsLoader`). **Les autres sites
  reviennent dans « Notes » seulement** (le développeur, 22/11/2026) : à l'ouverture de la fenêtre
  d'un film ou d'une série (`RatingButton(title:)`, jamais pour un épisode ni une carte),
  `externalRatingsProvider` demande `GET /catalog/ratings` (MDBList côté API) : Trakt,
  Letterboxd, Rotten Tomatoes (critiques et public), Metacritic, MyAnimeList, sous IMDb et TMDb,
  chacun sur son échelle (`RatingSite.scale`, `RatingSite.format` : « 79 / 100 », « 4,3 / 5 »),
  chacun avec son logo (`RatingLogo`, `RatingSite.logoAsset` : `assets/images/ratings/<site>.png`,
  tirés de `brand/ratings` : Simple Icons CC0, popcorn de Lucide ISC pour le public de Rotten
  Tomatoes, licence dans « Licences ») ; un site sans note n'apparaît pas ;
  `externalRatingsFromJson`. L'API importe chaque
  jour les jeux de données d'IMDb et donne `ratings` = `{imdb: {id, rating, votes} | null, tmdb:
  {rating, votes}}` avec la fiche (`TitleDetails.ratings`), chaque épisode d'une saison
  (`Episode.ratings`) et **toutes les listes de titres** (`MediaItem.ratings`, complété par
  `withDetails` ; demande du développeur, 21/11/2026 : la note IMDb partout, TMDb seulement en
  secours). Sans `ratings` (rangée légère de l'accueil pas encore complétée, titre que TMDb n'a pas
  pu donner) : **aucune note** (`MediaItem.shownRating` null), jamais `vote_average` seul, qui
  passerait pour la note choisie. Modèles `TitleRatings`, `SiteRating`, `RatingSite`
  (`catalog/models.dart`) ; aucune requête de note par carte. Affichage (`TitleRatings.shown`,
  `MediaItem.shownRating`) : **la note d'IMDb, sinon celle de TMDb**, chacune avec son logo
  (`RatingLabel` : étoile verte, « 8,8 », `RatingLogo` : `assets/images/ratings/imdb.png`, tiré de
  `brand/ratings/imdb.svg` par `brand/tools/rating_logos.py`, Simple Icons CC0 ; taille et forme
  par site : `RatingSite.logoHeight` / `logoAspect` ; TMDb : son logo officiel, `TmdbRating`), lu « Note IMDb : 8,8 sur 10 ». Cartes du téléphone (`CardRating`),
  grande image et carrousel (`TitleFacts`, avec le reste : rien ne bouge), fiche, épisodes.
  **Fiche : un appui sur la note** (`RatingButton`, petite flèche, focalisable à la télécommande)
  ouvre **« Notes »** (`showAllRatings`, `ratings_sheet.dart` : feuille du bas sur téléphone,
  fenêtre avec « Fermer » ailleurs) : IMDb puis TMDb, logo, nom, **nombre de votants**
  (`formatVotes` : « 2 400 000 votants ») et note « 8,8 / 10 », ou « Pas de note ». **Épisode** :
  sa note **juste à droite de la durée**, avec le logo du site (demande du développeur,
  21/11/2026) ; un appui dessus (ou appui long / touche menu sur la carte, à la télécommande)
  ouvre « Notes » ; rien en No spoil. Logo TMDb :
  `assets/images/tmdb_short.png` (« Primary short » de themoviedb.org converti en PNG sans
  modification). Pas de page de confidentialité ni de mention TMDb dans l'appli (décision du
  développeur). Tests : `test/ratings_test.dart`, `test/details_people_test.dart`.
- **Recherche** (`features/search`, API : filtres de `/catalog/{type}/discover` et `/catalog/search`) :
  barre de filtres `SearchFilterBar` (Tout / Films / Séries / Chaînes TV / Personnes, genre,
  années, tri ; « Catégorie » pour les chaînes) ; `SearchFilters` donne les paramètres de l'API.
  **« Années », « Note » et « Votants » : des intervalles choisis avec un curseur à deux poignées**
  (demande du développeur, 21/11/2026 ; `VxRangeSlider` / `showVxRange`, `core/widgets/range_slider.dart` :
  feuille du bas sur téléphone, fenêtre ailleurs, « Réinitialiser » et « Appliquer » ; télécommande :
  Gauche / Droite déplacent la poignée active, OK passe à l'autre ; positions de `RangeStops` :
  années de 1900 à cette année, notes de 0 à 10 par demi-points, votants de 0 à 1 000 000 et plus ;
  une poignée au bout de la piste = pas de limite ; puces « Depuis 2010 », « 2010–2019 »,
  « Note 6–8,5 », « Votants ≥ 10 000 » : `yearRangeLabel`, `ratingRangeLabel`, `votesRangeLabel` ;
  `pickYearRange`, `pickRatingRange`, `pickVotesRange` dans `filter_bar.dart`, aussi pour « Années »
  et « Note » de « Mes avis »). **« Note » et tri « Mieux notés »** (rétablis le 21/11/2026,
  `SearchFilterBar(withRating: true)`) et **« Votants »** portent sur **la note que montre chaque
  carte : IMDb, sinon TMDb**, et ses votants : la recherche les demande à l'API (`year_from` /
  `year_to`, `min_rating` / `max_rating`, `min_votes` / `max_votes`, `sort=rating`,
  `vixeo_backend/docs/notes.md`) ; « À voir », qui filtre et trie elle-même, les applique de la
  même façon (`SearchFilters.yearWithin`, `ratingWithin` : un titre sans note est écarté par une
  borne). **« Chaînes TV » et « Personnes » toujours proposés**, avec ou sans texte
  (demande du développeur) : dans « Tout », après Films et Séries, une section « Chaînes TV » et
  une section « Personnes » toujours affichées (une ligne « Aucune … » si vide ; masquées avec un
  filtre genre / années, qui ne s'applique qu'aux titres). **Sans texte** : champ vide → les
  recherches récentes ; **avec un filtre (genre, années, note) ou un tri choisi, les films et
  séries qui y répondent** (demande du développeur, 21/11/2026 : « les films d'horreur depuis
  2010 notés 8 et plus » ; `SearchFilters.canBrowse`, API `/catalog/discover` et
  `/catalog/discover/{type}` via `searchProvider` / `titlesProvider` avec un texte vide ; ni
  chaînes, ni personnes, ni comptes ; pas de « Pertinence »). Avec une borne de note ou de
  votants, une page de l'API peut
  être courte ou vide : `PagedGrid` lit les suivantes (10 pages vides au plus) avant « Aucun
  résultat ». Un texte en cours de saisie (ou d'une seule lettre) → rien, ni récentes ni « Aucun
  résultat » ; « Aucun résultat » uniquement quand une recherche ne trouve rien (dans « Tout » :
  ni titre, ni personne, ni chaîne). Sur TV, le
  champ ne prend pas le focus à l'arrivée (il ouvrirait le clavier).
  « À voir » reprend la barre sans « Personnes » ni « Catégorie » (`kinds`, `channelCategories`). Avec un texte : l'API filtre et trie les premiers résultats (une
  recherche filtrée ne renvoie pas de personnes). « Tout » = une rangée Films et une rangée
  Séries, puis Personnes et Comptes, chacune avec le **bouton rond « Voir tout »** à droite de son
  titre (demande du développeur, 21/11/2026 ; `SectionHeader(onSeeAll:)`) : il choisit ce type,
  comme sa puce (`filtersOfKind`, même texte et mêmes filtres, page remise en haut) ; un type choisi = une grille qui charge la page suivante en arrivant à la fin
  (`_PagedGrid`). Téléphone : pas de carrousel ni de grande image (demande du développeur) ;
  grand écran : la grande image (`catalog/hero.dart`, partagée avec l'accueil) montre le premier
  résultat, puis suit la carte sélectionnée ou survolée. Un genre absent du type choisi est
  retiré. Recherches récentes synchronisées entre les appareils du profil
  (`RecentSearches`, API `/profiles/{id}/searches`) : affichées tout de suite, enregistrées en
  arrière-plan, 8 visibles sur 20 gardées ; « orbi » puis « orbite » ne garde que « orbite » (même
  règle que l'API). Pas de page par genre : on filtre par genre dans la recherche.
- **Fiche : « Distribution » et « Équipe technique »** (demande du développeur, 25/11/2026 :
  deux rangées) : « Distribution » (les acteurs, leur personnage) puis « Équipe technique » (tous
  les autres, une fois chacun avec **leurs métiers en français** : « Réalisation, Scénario »,
  « Musique »… ; `TitleDetails.crew`, `crew` de l'API, les plus importants d'abord, création d'une
  série en tête), 20 chacune, chacune avec son « Voir tout » (`CreditsScreen`,
  `/titre/:type/:id/distribution` et `/titre/:type/:id/equipe`, `titleCreditsProvider` /
  `titleCrewProvider`, API `credits` et `credits?group=crew`). Pas de ligne « Avec … · Réalisation :
  … » sous le résumé (demande du développeur). Les cartes de personnes passent toutes par
  `PersonCard` (`catalog/widgets.dart`, fiche et recherche) : nom et rôle sur deux lignes au plus,
  pour ne pas les couper.
- **Logo du titre** (`TitleLogo`, `catalog/widgets.dart`) : fiche, grande image (accueil et
  recherche) et carrousel du téléphone écrivent le titre avec le logo TMDb (`logo_url`),
  dimensionné avant son chargement (`logo_aspect_ratio`) ; sans logo, ou s'il ne se charge pas, le
  nom est écrit. L'accueil et la recherche donnent le logo avec chaque titre (logo tout de suite) ;
  pour « Continuer à regarder », il vient de la fiche quand la sélection s'arrête, dans une
  place de hauteur fixe (rien ne bouge). Carrousel du téléphone : pleine largeur, image de fond
  (`backdrop`), logo, informations données avec le titre et bouton « Voir la fiche ». Fond de
  la fiche : l'image sans texte
  (`textless_backdrop_url`, via `TitleDetails.background(size)`), sinon `backdrop_url`. Le lecteur
  d'écran lit toujours le nom.
- **Paramètres du profil** (`/profil/parametres`, `ProfilePreferencesScreen`, API :
  `vixeo_backend/docs/lecture.md`) : langue audio préférée (null = version originale), langue des
  sous-titres (null = désactivés ; noms dans `profiles/languages.dart`, mêmes codes que l'API) et
  « Passer automatiquement » le générique de début, le résumé, le générique de fin, l'aperçu
  (sinon le lecteur montrera un bouton « Passer »). Champs du profil unique : synchronisés. Le lecteur n'existe pas encore : `features/playback` (`PlaybackRepository`,
  `SkipSegments.at`, `SkipKind.autoFor`) prépare ce qu'il utilisera. Les applis ne parlent jamais
  à OpenSubtitles ni à TheIntroDB : tout passe par l'API (clé Vixeo commune).
- **Affiches, arrière-plans et logos** (demande du développeur, 25/11/2026, d'après une autre appli
  de films ; API : `vixeo_backend/docs/images-des-titres.md`) : le **« ⋮ » en haut à droite de la
  fiche** (connecté avec un profil ; plus de bouton rond « Affiches, arrière-plans et logos »,
  demande du développeur, 25/11/2026 : `_TitleMenuButton`, liste déroulante `showVxMenu`) propose
  « Changer l’affiche », « Changer l’arrière-plan », « Changer le logo », qui ouvrent chacun leur
  onglet de `ArtworkScreen` (`/titre/:type/:id/images?sorte=affiche|arriere-plan|logo`,
  `ArtworkKind.slug`, `catalog/artwork_screen.dart`) : en-tête au nom de l'onglet, `VxTabs`
  Affiches / Arrière-plans / Logos, grille (`imageGridDelegate`) avec **« Par défaut »** (l'image de
  TMDb) en premier puis les images de TMDb (`titleImagesProvider`, `GET /catalog/{type}/{id}/images`) ;
  l'image choisie a un anneau vert ; **un appui choisit tout de suite** (`chooseTitleImage`,
  `PUT /profiles/{id}/artwork/{type}/{id}`, remis en cas d'échec). **L'API applique le choix**
  partout où elle donne le titre au profil (listes, recherche, accueil, fiche) : après un choix,
  `catalogEpochProvider` monte et tous les providers du catalogue relisent (ils surveillent
  `_catalogKeyProvider` : profil actif + époque). Test : `test/artwork_test.dart`.
- **Pas de section « Sources »** sur la fiche (demande du développeur).
- **« Bandes-annonces »** (demande du développeur, 25/11/2026 : une rangée comme la filmographie,
  **plus de bouton « Bande-annonce »**) : sur la fiche, après les épisodes, une rangée de toutes
  les bandes-annonces et teasers (`TitleDetails.trailers`, `trailers` de l'API, le meilleur
  d'abord ; une API d'avant ne donnait que `trailer`) : `_TrailersRow`, cartes `_TrailerCard`
  (image 16:9 de YouTube recadrée, rond « lecture », badge « Teaser », nom sur deux lignes ; 240
  téléphone, 280 tablette, 440 TV ; lues « Bande-annonce : … » / « Teaser : … ») ; un appui
  l'ouvre sur YouTube (`launchUrl`, application externe).
- **Bouton retour toujours visible** (demande du développeur, 25/11/2026) : sur une page dont le
  contenu défile sous le haut de l'écran (fiche, page d'une personne, pages de profil, « Voir
  tout » du catalogue, chaîne), le retour (et les boutons de droite : « ⋮ », partage…) reste en
  haut quand on fait défiler : `VxFloatingBar` (`core/widgets/page_header.dart`), dernier enfant
  d'un `Stack` au-dessus de la page (`Positioned(top: 0, left: 0, right: 0)`), place laissée en
  haut de la page (`VxFloatingBar.heightOf`) ; chaque bouton de droite sur un rond sombre. Fiche
  grand écran : « Retour » avec son mot (`_LargeBack`). Les pages à `VxPageHeader` ou `InfoPage`
  gardent leur en-tête fixe. Test : `test/tmdb_test.dart`.
- **Épisodes d'une série** (`_Episodes`, `_EpisodeCard`, `catalog/details_screen.dart` ; demande
  du développeur) : sous les puces des saisons, une **rangée horizontale** de grandes cartes
  (largeur 300 téléphone, 340 tablette, 520 TV) qui défile de gauche à droite. Carte : image 16:9
  avec le badge « Épisode 3 » en haut à gauche ; **le texte est sur l'image, en bas**, sur un
  dégradé sombre (demande du développeur) : le titre (1 ligne), le résumé (**2 lignes au plus**,
  pour laisser voir l'image) et, sur la dernière ligne, la durée puis juste à sa droite la note
  (IMDb, sinon TMDb, avec le logo du site, qui ouvre « Notes » : voir « Notes des titres ») à
  gauche, la date de diffusion à droite ; ni durée, ni date, ni note en No spoil. En haut à
  droite, l'étoile pour noter l'épisode et, après « Épisode 3 », « Ma note : 8/10 » (voir « Avis »). Hauteur de carte fixe (`_EpisodeCard.heightOf` : 16:9, plus haute
  seulement si le texte du système est très grand). Changer de saison revient au premier épisode. Test :
  `test/details_people_test.dart`.
- **Affiches : format vertical seulement** (demande du développeur, 25/11/2026 : plus de réglage
  « Format des affiches », `PosterFormat` et `poster_format` supprimés, ni de carte horizontale ;
  l'affiche porte déjà le titre, **aucun logo à charger pour une carte**, `cardLogoUrl` et
  `ImagesTogether` supprimés). `PosterRow` / `PosterGrid`, `PosterCard` (2:3). **Sur téléphone**
  (demande du développeur), sous chaque affiche : le titre sur une ligne, puis l'année à gauche et
  la note (IMDb, sinon TMDb) avec le logo du site à droite (`CardRating` ; hauteur
  `PosterCard.captionHeightOf(context)`, que les rangées et les grilles ajoutent à l'image ;
  grilles : `posterGridDelegate(…, captionHeight:)`). **Tablette et TV : pas de nom sur les
  affiches** (l'image suffit) ; le nom n'est écrit que pour un titre sans aucune image, et reste
  dans le libellé pour les lecteurs d'écran. **Jamais de requête de fiche par carte**
  (`titleProvider` dans `PosterCard` = une requête par titre affiché, au-delà de la limite de
  l'API). « À voir » demande ses titres 20 à la fois, au fil du défilement (`titlesByIdProvider`,
  API `/catalog/titles`). Badge « Ma liste » sur l'affiche, « vu » dans le libellé. Titre de rangée
  et lien « Voir tout » : `SectionHeader(title, onSeeAll: …)`. Pages principales (Recherche,
  « À voir », Avis) : même en-tête `VxPageHeader` (titre, recherche, `FilterBar`) et
  `pageContentPadding` (charte, § 6).
- **Avatars** : galerie `GET /avatars` regroupée par licence (`features/profiles/avatars.dart`,
  pixel art dessiné par `PixelAvatarPainter`, ou `image_url`) ; `ProfileAvatar` partout où le
  profil apparaît. Uniquement des avatars originaux, ou de licences dont on a les droits. Chaque
  nouveau profil (y compris celui créé à l'inscription) reçoit un avatar du catalogue au hasard
  (côté API) ; l'avatar se choisit dans « Ajouter / Modifier le profil » (« Ajouter » de « Qui
  regarde ? », « ⋮ » → « Modifier mon profil ») : **plus de page ni de tuile « Avatar » dans les paramètres** (demande
  du développeur). L'initiale reste affichée pour un
  ancien profil sans avatar.
  **Photo de profil** (demande du développeur, 23/11/2026 : « pour laisser le choix » ; API :
  `vixeo_backend/docs/social.md`) : carte « Photo de profil » de « Ajouter / Modifier le profil »
  (« Importer une photo », « Changer la photo », « Retirer la photo » ; pas d'import sur TV,
  `canChooseProfilePhoto`) ; la photo choisie (`FilePicker`, image) s'ouvre sur **« Cadrer la
  photo »** (`PhotoFramingScreen`, `profiles/profile_photo.dart` : carré avec un rond-guide,
  déplacer au doigt ou à la souris, zoomer en pinçant, à la molette ou avec « Zoomer » /
  « Dézoomer » ; photo décodée à 2 048 px au plus) ; « Utiliser cette photo » rend un carré PNG de
  512 px, envoyé à l'enregistrement (`uploadProfilePhoto`, `POST /profiles/{id}/photo` ; retrait :
  `DELETE`). **Choisir un avatar retire la photo** (aucun avatar marqué tant qu'il y a une
  photo). Affichage : `AvatarTile(photoUrl:)` (la photo, sinon l'avatar, sinon l'initiale ;
  l'avatar sous la photo pendant son chargement), `photoUrl` dans `Profile`, `SocialProfile` et
  `ChatMember` (`photo_url` de l'API) : **tout `AvatarTile` d'un profil reçoit sa photo**. Tests :
  `test/profiles_screen_test.dart`, `test/models_test.dart`.
  **Couverture** (demande du développeur, 24/11/2026 ; API : `vixeo_backend/docs/social.md`) : la
  bannière 3:1 en haut de la page d'un profil. Une couverture du catalogue (`GET /covers`, par
  style : Dégradés, Lumières, Motifs, Cinéma ; `coverCatalogProvider`, `coverByIdProvider`) n'est
  pas une image : un motif et ses couleurs **dessinés par l'appli** (`profiles/covers.dart`,
  `CoverPainter` : `linear`, `glow`, `stripes`, `dots`, `waves`, `grid`, `film`, `spotlight`,
  `curtain`, `stars` ; motif inconnu : dégradé de ses couleurs ; sans couverture : « Aurore »,
  `CoverDef.fallback`), ou **son image** (`cover_url`, `ProfileCover(imageUrl:)` : la couverture du
  catalogue dessous pendant le chargement). **Le profil initial reçoit une couverture au hasard à l'inscription.** Carte
  « Couverture » de « Ajouter / Modifier le profil » (`_CoverCard`) : « Importer une image » /
  « Changer l'image » / « Retirer l'image » (pas d'import sur TV), puis les couvertures par style
  (vignettes 3:1, coche verte) ; **choisir une couverture retire l'image** ; l'image choisie s'ouvre
  sur **« Cadrer la couverture »** (`PhotoFramingScreen(shape: FramingShape.cover)`, la même page que
  la photo : cadre 3:1, PNG 1 500 × 500), envoyée à l'enregistrement (`uploadProfileCover`,
  `POST /profiles/{id}/cover` ; retrait : `DELETE`). `cover` / `coverUrl` dans `Profile` et
  `SocialProfile`. Tests : `test/covers_test.dart`, `test/profiles_screen_test.dart`.
- **Pages de profil** (demande du développeur) : « Profil » (onglet `/profil`, `ProfileScreen`)
  et la page d'un membre (`/membre/:username`, `PublicProfileScreen`) sont **la même page** :
  le composant `ProfileView` (`features/social/profile_view.dart`) et ses morceaux
  `ProfileHeader`, `ProfileStats`, `ProfileTitlesSection`, `ProfileReviewsSection`,
  `ProfileSectionMessage` / `ProfileSectionLoading`. **Modifier la page = modifier ce fichier**
  (pas de copie dans les écrans) ; chaque écran ne donne que ses données et son bouton. **Mise en
  page d'après Bingers** (demande du développeur, 25/11/2026). En haut, **la couverture**
  (`ProfileView(cover: ProfileCover(…))`, 3:1, 200 de haut au plus (TV 340) : toute la largeur sur
  téléphone, dans la colonne aux coins arrondis ailleurs ; voir « Avatars ») et dessus, **fixes
  quand la page défile** (`VxFloatingBar`), le retour (un membre), **« Partager le profil »**,
  puis, pour le mien, la cloche « Notifications » et **« ⋮ »** (« Plus d’options », toutes les
  tailles d'écran ; plus de bouton « Paramètres »), pour un membre **« ⋮ »** (masquer, bloquer,
  signaler), sur une ombre légère. **« ⋮ » ouvre une liste
  déroulante** sous le bouton (`showVxMenu`, `core/widgets/menu.dart` : une route transparente
  placée à côté du bouton, alignée à droite, au-dessus faute de place ; lignes `VxFocusable`, la
  première a le focus ; Retour ou un appui à côté la ferme) : **« Modifier mon profil »**
  (`/profils/modifier/:id`), **« Paramètres »** (`/parametres`),
  **« Comptes bloqués et masqués »** (`/profil/comptes-masques`), **« Se déconnecter »** (rouge).
  **En-tête aligné à gauche** : l'avatar à gauche, à moitié sur la couverture (anneau de la
  couleur de la page) et, à sa droite sous la couverture, les boutons d'un membre (« Envoyer un
  message » rond, puis « Suivre » / « Ne plus suivre », focus à l'arrivée ; invité : « Se connecter
  pour suivre ») ; dessous le nom, @pseudo, « 82 % de goûts en commun », **« 3 Abonnements »,
  « 12 Abonnés »** et **« 8 Personnes suivies »** (nombre en gras ; acteurs, réalisateurs… ;
  `people_count` de l'API, le mien depuis la synchro ; chacun ouvre sa liste ; lus « 12 abonnés »),
  biographie (**160 caractères au plus**, demande du développeur, 21/11/2026 : `bioMaxLength`, même
  limite dans l'API ; rien quand il n'y en a pas) et réseaux. **Pas de bouton sur ma page**
  (biographie, réseaux et compte privé dans « Modifier mon profil » ; l'onglet affiché prend le
  focus à l'arrivée, `ProfileView(focusTabs:)`). Puis **les chiffres** (`ProfileStats`, une carte
  chacun, libellé en capitales au-dessus de la valeur) : **« Temps de visionnage »**
  (`watch_minutes` de l'API, `watchTimeLabel` : « 3 mois 21 j 9 h », « 5 h 12 min », un mois =
  30 jours ; lu « 3 mois, 21 jours et 9 heures »), « Films et séries vus », « Épisodes vus »
  (`episodes_count`), « Avis », « À voir » ; **téléphone : ils défilent de gauche à droite** (deux
  cartes et le bord de la troisième) ; tablette et TV : ils se partagent la largeur de la colonne
  (rien à faire défiler à la télécommande). Puis les cinq onglets (voir « Page de profil » du réseau social :
  Activité, Listes, Avis, Aimés, Vus ; grilles d'une seule requête `titlesByIdProvider` via
  `withCatalogDetails`) ; le bouton rond « Voir tout » ouvre `/listes/a-voir`, `/avis`,
  `/profil/social/aimes|vus|personnes` (le mien) ou `/membre/:username/a-voir|avis|aimes|vus|
  personnes|abonnes|abonnements` (**adresses en français seulement**, plus de `list`, `liked`,
  `reviews`… : une autre section affiche « Page introuvable ») : **les mêmes pages** « À voir »,
  J'aime, titres vus (`MyListScreen(username:, collection:)`, sans les chaînes) et « Ses avis »
  (`ReviewsScreen(username:)`), avec recherche, filtres et tri (demande du développeur) ;
  `SocialCollectionScreen` n'affiche lui-même que les abonnés / abonnements et les personnes. Ouvertes par-dessus une autre page, elles ont le bouton retour de
  `VxPageHeader(back:)` (`VxBackButton`) ; pas les onglets. Un avis d'un membre (`ReviewRow(mine: false)`) ouvre la fiche du
  titre, pas « Mon avis ». Le mien : liste de la synchro (`libraryProvider`) et première page de
  mes avis (`myReviewsProvider`). Un membre (première page de chacun) :
  `socialProfileProvider`, `socialTitlesProvider`, `socialWatchedProvider`, `socialReviewsProvider` (API
  `/social/profiles/{username}…` ; les avis ont les champs de « Mes avis »). Le profil unique est la page publique du compte dès qu'un pseudo est défini. **Comptes** (recherche, abonnés) : `AccountTile` = avatar, nom, @pseudo, **sans le
  nombre d'abonnés** (demande du développeur). **La recherche ne montre jamais le profil actif
  lui-même** (demande du développeur, 20/11/2026 : on ouvre son profil par la navigation,
  « Profil ») : l'API le retire et `socialSearchProvider` aussi. **« Partager le profil »**
  (demande du développeur, 21/11/2026 ; **en haut à droite, à côté de « Paramètres »** depuis le
  23/11/2026) : bouton rond des `actions` de `ProfileView` (mon profil et celui d'un membre ; **pas
  sur TV**, `canShareLinks`),
  qui envoie la page du profil sur le site (`share_url` de l'API, `www.vixeo.app/pseudo`, **sans @,
  comme Twitter**, demande du développeur, 21/11/2026) :
  feuille de partage d'Android (`LinkSharer`, `core/share.dart`, canal `app.vixeo/share` de
  `MainActivity.kt`), sinon (Windows) lien copié et « Lien copié ». **Lien d'un profil** :
  Android ouvre `https://www.vixeo.app/pseudo` dans l'appli (Android App Links, `assetlinks.json` du
  site avec l'empreinte du certificat de release, `flutter_deeplinking_enabled`) : alias
  `.ProfileLinkActivity` du manifeste (`pathAdvancedPattern="/[A-Za-z0-9_]+"`, **Android 12 et
  plus** seulement, `values-v31/bools.xml` : avant, l'attribut serait ignoré et toutes les pages du
  site s'ouvriraient dans l'appli ; ces versions ouvrent la page du site), plus `/membre/pseudo`, la
  page de l'appli (filtre `pathPrefix`, toutes versions, utilisée par « Ouvrir dans Vixeo » du site).
  Le routeur en fait `/membre/pseudo` (`memberOfLink`), ou `/profil` pour mon propre profil :
  `/pseudo` est **la dernière route** (`profileLinkRoute`, `profileLinkPath`), donc seulement un
  mot qui n'est aucune page de l'appli (l'API réserve ces mots : `Usernames::RESERVED`, à compléter
  pour toute nouvelle page d'un seul mot). Test : `test/profile_screen_test.dart`.
- **Espacements** (charte, § 5) : les écarts d'une page ont un nom dans `core/design.dart`
  (`layout.sectionGap`, `titleGap`, `introGap`, `listGap`, `cardGap`) et le bas d'une page qui
  défile passe par `pageBottomPadding(context)` (place de la barre d'onglets comprise). Pages
  secondaires : `InfoPage` / `InfoBody`, `InfoIntro`, `InfoSection`, `VxCard`, tout aligné sur
  la colonne (pas de retrait). « Paramètres » (onglet) a le `VxPageHeader` des pages
  principales. Paramètres du profil : chaque groupe passe par `_Section`
  (`profile_preferences_screen.dart`). Tests : `test/design_test.dart`.
- **Logo** (`brand/README.md`) : V blanc, triangle vert, « Vixeo » en Sora ExtraBold, couleurs
  de la charte, **le même partout** (demande du développeur) : `VxLogo` dans l'appli (mêmes
  formes que `brand/vixeo-logo.svg`), icône Android adaptative
  (`mipmap-anydpi-v26`, `drawable/ic_launcher_foreground.xml`) et PNG d'avant Android 8, bannière
  Android TV (`drawable/tv_banner.xml`), icône Windows (`windows/runner/resources/app_icon.ico`),
  icônes iOS (`AppIcon.appiconset`), site et favicon de `vixeo_backend`. Tout est généré par `brand/tools` : changer le logo là, puis recopier.
- **Images** : `NetImage` (cache, couleur de remplacement). Tailles TMDb via
  `MediaItem.poster('w780')` / `backdrop('original')`, dérivées des URL renvoyées par l'API.
  **Décodées à la taille affichée** (`NetImage.decodeWidth` : largeur de la place × densité,
  arrondie à 128, assez large pour une image qui couvre une place haute) et non à celle du
  fichier (une image de fond TMDb fait jusqu'à 3840 pixels : mémoire et lenteur sur TV).
- Tests : `flutter test` ne charge pas les polices (texte de remplacement), sans réseau.
- **CI** (`.github/workflows/build.yml`) : `flutter analyze` (les erreurs bloquent) et
  `flutter test` d'abord ; puis, sur `main`, APK signé publié en release GitHub `android-<n>` et
  installateur Windows (`windows-latest`, Inno Setup) publié en release `windows-<n>` (lues par
  l'API pour les mises à jour et par le site) ; APK de debug pour les pull requests. **Plus de
  build web ni de déploiement Forge** (demande du développeur, 20/11/2026). Couleurs
  des actions destructives : `VxColors.danger` / `dangerText`, `VxButtonKind.danger`.

## Branches

- Le travail se fait **directement sur `main`** (demande du développeur).

## État actuel

- Fait : connexion (e-mail, Google et Apple dans un navigateur), inscription, session persistante (jeton chiffré), connexion TV par code
  (tapé dans l'appli du téléphone), profil unique résolu automatiquement après la connexion, accueil (carrousel / grande image, « Continuer à regarder », rangées),
  fiche film et série (saisons, épisodes avec date de diffusion, distribution, recommandations,
  bande-annonce, « À voir » et listes, Vu, avis sur le film et la série), page personne (`/personne/:id` : biographie, « Connu pour », filmographie ; ouverte depuis
  la distribution et la recherche), recherche (filtres type / genre / années, tri, grande image
  sur grand écran, résultats groupés, recherches récentes synchronisées), notes IMDb (jeux de
  données importés par l'API) sinon TMDb, avec leurs votants (« Notes »), sur les titres et les épisodes,
  « À voir », « Avis » (notes et commentaires), « Mon profil » (paramètres
  d’apparence, No spoil, langues et lecture automatique,
  connecter une TV, Notifications (nouveaux épisodes, activité ; Windows par le
  canal temps réel, appli ouverte),
  déconnexion, mon compte : export et suppression, appareils connectés), mot de passe oublié,
  vérification des
  mises à jour (Android / Windows, installées depuis l'appli), TV en direct (catégories, chaînes, lecture du flux), lecteur à
  moteurs par plateforme (natif sur Android / iOS, media_kit sur Windows : `docs/lecteur.md`),
  appli Windows (fenêtre, plein écran, installateur), mises en page téléphone et TV / grand
  écran, navigation à la télécommande.
- Fait aussi : messagerie (conversations directes et demandes, groupes, photos et vidéos, accusés
  de lecture, blocage) en temps réel (Reverb), page « Lire la suite » des résumés et biographies,
  notes des autres sites dans « Notes » (MDBList).
- Fait aussi : page « Notifications » de la navigation (demandes d'abonnement, prochains épisodes
  de « À voir », activité, pastille des non lues), compte privé et demandes d'abonnement,
  réseaux sociaux du profil, J'aime sur les avis des autres membres, push « Activité ».
- Fait aussi (23/11/2026) : réseau social des films et séries (fil d'actualité avec avis, vus,
  J'aime et listes, avis et commentaires avec spoilers, listes ordonnées avec « À voir » en tête,
  choix de la liste au marque-page, page de profil en cinq onglets dont l'activité datée,
  bilan de l'année, partage en image, fiche sociale, goûts en commun, premier lancement, signaler /
  bloquer / masquer, note proposée en fin de lecture avec son réglage). **Pas encore vérifié sur un
  appareil** (la CI compile et teste).
- Notarisation Apple : audit et état des corrections dans `APPLE_NOTARIZATION.md`.
- Vérifié de bout en bout (ancienne version web) contre l'API Laravel locale avec un faux TMDb.
- Pas encore vérifié sur un vrai PC Windows : lecture (media_kit), mise à jour par l'installateur,
  notifications (canal temps réel) ; la CI ne fait que compiler (matrice de
  `docs/lecteur.md`, `docs/windows-release.md`).
- Pas encore fait : appli iOS ; moments à passer et langues préférées du profil pas encore
  utilisés par le lecteur (les sous-titres de l'API, si) ; signature de l'installateur Windows.

# Vixeo — appli Flutter (vixeo_frontend)

Appli **Vixeo** (media center) pour le web, Android, Android TV / Google TV et iOS, avec une
seule base de code. L'API Laravel est dans
[`davybrieu/vixeo_backend`](https://github.com/davybrieu/vixeo_backend).

**Lire d'abord [`docs/CONTEXT.md`](docs/CONTEXT.md)** (copie de celui de l'API) : décisions produit,
périmètre légal (§3 : ce qui est hors périmètre ne doit pas être implémenté), sécurité (§6).

**Écarté par le développeur** (ne pas proposer) : import IPTV / M3U / Xtream, radio, replays.

**Distribution Android** (décision du développeur, ne plus poser la question) : **pas de Play
Store**. L'appli Android (téléphones, tablettes, Android TV / Google TV) est distribuée en
**APK signé** depuis le site `vixeo_web` (page `/installer`). Conséquences :
- chaque version est signée avec la **même clé de release** (keystore hors du dépôt, dans les
  secrets) : sinon Android refuse d'installer la mise à jour par-dessus l'ancienne version ;
- les mises à jour passent par la vérification intégrée à l'appli (`GET /app/update`), pas par
  un store ;
- vérification des développeurs Android par Google : obligatoire hors Play Store dans 4 pays
  depuis le 30/09/2026, prévue partout en 2027 : enregistrer le développeur dans l'Android
  Developer Console avant.

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
flutter run -d chrome --dart-define=API_URL=http://localhost:8000
flutter run -d <android> --dart-define=API_URL=http://10.0.2.2:8000   # émulateur Android
flutter build web --release --dart-define=API_URL=https://api.<domaine> \
  --dart-define=PUBLISHER_NAME="…" --dart-define=SUPPORT_EMAIL=support@<domaine>
```

Une version Release refuse de démarrer sans `API_URL` en `https://`, ni sans `PUBLISHER_NAME` et
`SUPPORT_EMAIL` (`AppConfig.configurationError`).

Dans un conteneur Claude Code cloud, Flutter n'est pas préinstallé : voir le script de
`docs/CONTEXT.md` §7 (clone du canal stable dans `/opt/flutter`). Pas de SDK Android ni de
Xcode : seules les cibles web et les tests se vérifient dans le conteneur.

## Structure

```
lib/
  main.dart, app.dart, router.dart   entrée, thème, raccourcis télécommande, routes
  core/
    config.dart                      API_URL (--dart-define), contrôle de la configuration en Release
    legal.dart                       éditeur et adresse de support (--dart-define)
    theme.dart                       couleurs (VxColors), polices Sora / Inter (VxText)
    device/layout.dart               téléphone / tablette / grand écran, détection TV, échelle TV
    api/                             client HTTP (dio), erreurs en français, stockage du jeton
    widgets/                         VxFocusable (focus TV), boutons, images, états vides / erreur
  features/
    auth/        connexion (page d'accueil de l'appli), inscription, mot de passe oublié, session,
                 connexion TV par QR code (device_login.dart : carte TV + page /tv)
    account/     Mon compte (export, suppression), appareils connectés, confidentialité, aide
    updates/     vérification des mises à jour Android / iOS (UpdateGate, écrans)
    profiles/    « Qui regarde ? », PIN, ajout, « Mon profil », avatars, contrôle parental
    catalog/     modèles TMDb, accueil, fiche film / série, page personne, cartes et rangées
    library/     synchro par profil (favoris, vus, « Continuer à regarder »), Ma liste
    search/      recherche : « Explorer » sans texte, filtres (type, genre, années, note) et tri,
                 recherches récentes synchronisées (search_history.dart)
    playback/    pour le futur lecteur : moments à passer (TheIntroDB) et sous-titres (OpenSubtitles),
                 via l'API
    shell/       navigation : onglets en bas (téléphone), rail à gauche (TV, tablette, ordi)
```

## Conventions

- **État** : Riverpod 3 (`Provider`, `FutureProvider.family`, `Notifier`, `AsyncNotifier`), sans
  génération de code. Les providers du catalogue surveillent le profil actif : changer de profil
  recharge les données (l'API filtre selon l'âge du profil).
- **Navigation** : go_router. La connexion est la page d'entrée ; le routeur redirige vers
  `/connexion` tant qu'on n'est pas connecté, puis vers `/profils` tant qu'aucun profil n'est choisi.
  Le routeur n'écoute que le statut de connexion et la présence d'un profil : modifier le profil
  (avatar…) ne doit pas reconstruire les pages. Exception : `/tv` (validation d'une TV) ne demande
  pas de profil ; ouvert sans être connecté, il est mémorisé et rouvert juste après la connexion.
  `/confidentialite` et `/a-propos` sont lisibles par tous, à tout moment (la politique est aussi
  l'URL donnée à Apple) ; `/mot-de-passe-oublie` est une page de connexion.
- **Connexion TV par QR code** (`features/auth/device_login.dart`, API : `vixeo_backend/docs/connexion-tv.md`) :
  sur grand écran, la page de connexion affiche `TvCodeCard` (QR code vers `<WEB_URL>/tv?code=…`
  + code court), qui interroge `/auth/device/token` toutes les `interval` secondes et demande un
  nouveau code sur un 410. Le téléphone valide sur `/tv` (« Mon profil » → « Connecter une TV »).
  Le `device_code` reste en mémoire, jamais dans une URL.
- **Contrôle parental** (`features/profiles/parental_control_screen.dart`, route
  `/profil/controle-parental`) : si un PIN parental existe, il est demandé à l'arrivée, gardé en
  mémoire tant que la page est ouverte et envoyé (`parental_pin`) avec chaque modification de
  profil ; « Code oublié ? » désactive le contrôle avec le mot de passe du compte. Après une
  modification : invalider `profilesProvider` et `homeProvider` (le catalogue dépend des limites).
- **Confidentialité** (`features/account/privacy_screen.dart`) : le texte décrit exactement ce que
  l'appli et l'API font (`APPLE_NOTARIZATION.md` §5). Toute nouvelle donnée, tout nouveau service
  tiers ou SDK : mettre à jour ce texte, `Legal.privacyPolicyDate`, `ios/Runner/PrivacyInfo.xcprivacy`
  et l'audit. Pas de SDK de publicité, de suivi ou d'analytics ; aucune permission iOS sans besoin.
- **Mises à jour** (`features/updates`, API : `vixeo_backend/docs/mise-a-jour.md`) : sur Android et
  iOS, `UpdateGate` (dans le `builder` de `MaterialApp.router`) interroge `GET /app/update` avec le
  **build** installé (`package_info_plus`) au lancement et au retour au premier plan (toutes les 6 h
  au plus). `update_required` → écran « Mise à jour nécessaire » à la place de l'appli ;
  `update_available` → proposition une fois par lancement. Une vérification qui échoue ne bloque
  jamais. Sur Android (pas de Play Store), « Mettre à jour » (`UpdateButton`) télécharge l'APK
  (`latest.download_url`, https uniquement, sans le jeton Vixeo), vérifie son SHA-256, puis ouvre
  l'installateur d'Android (`ApkInstaller`, canal `app.vixeo/updates` dans `MainActivity.kt`,
  `FileProvider` sur `cache/updates`, permission `REQUEST_INSTALL_PACKAGES`), qui demande une
  confirmation. Sans APK, ou sur iOS, le bouton ouvre la page d'installation du site. L'appli ne
  charge jamais de code qu'elle exécuterait elle-même. Publication : `docs/android-release.md`. Le web ne vérifie pas. Pour essayer dans un navigateur :
  version « profile » avec `--dart-define=UPDATE_PLATFORM=android`.
- **Version et signature** : `version: x.y.z+build` dans `pubspec.yaml`. Le build doit augmenter à
  chaque version publiée. La version Release est signée avec la clé de release
  (`android/key.properties` ou variables `VIXEO_KEYSTORE_*`, jamais dans le dépôt) ; sans clé, le
  build Release échoue. Puis la version est déclarée côté API (`php artisan vixeo:release`, avec
  `--apk` et `--sha256`). Détails : `docs/android-release.md`.
- **Polices** : Sora et Inter sont dans `assets/fonts` (licence OFL) ; rien n'est téléchargé au
  lancement (pas de `google_fonts`).
- **API** : passer par `ApiClient` (jeton Bearer + en-tête `X-Profile-Id` ajoutés automatiquement,
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
  - les tailles TV sont celles du design 1920×1080, converties avec `Layout.of(context).tv(px)` ;
  - les rangées horizontales sont dans un `FocusTraversalGroup` ;
  - accueil grand écran : la grande image et ses informations suivent la carte sélectionnée
    (focus : tout de suite) ou survolée à la souris (`onHovered`, après 150 ms), rangée
    « Continuer à regarder » comprise. Quand la sélection reste 400 ms sur un titre, sa fiche
    (`titleProvider`) ajoute genres, durée ou saisons et âge conseillé. À l'arrivée, la première
    carte de la première rangée (« Continuer à regarder » s'il y en a, sinon la première liste) a
    le focus et occupe la grande image : pas de « titre à la une » (`featured`) sur grand écran,
    ni de bouton « Plus d'infos » ; OK ou un clic sur la carte ouvre la fiche. Le carrousel du
    téléphone garde les titres à la une.
- **Actions sur un titre** (Ma liste, Vu / non vu, Bande-annonce) : toujours le même bouton
  rond **icône seule** (`VxIconAction`, `FavoriteButton`, `WatchedButton`), sans texte visible
  (libellé pour les lecteurs d'écran uniquement). Le même bouton ajoute et retire. Chaque action
  se confirme par une alerte (`showVxSnack`) : « Ajouté à votre liste », « Supprimé de votre
  liste », « Marqué comme vu », « Marqué comme non vu » (`features/library/actions.dart`).
- **Recherche** (`features/search`, API : filtres de `/catalog/{type}/discover` et `/catalog/search`) :
  barre de filtres `SearchFilterBar` (Tout / Films / Séries / Personnes, genre, années, note
  minimale, tri) ; `SearchFilters` donne les paramètres de l'API. Sans texte : « Explorer » tout le
  catalogue (`/discover`, tri par popularité par défaut ; « Personnes » et « Pertinence »
  n'existent qu'avec un texte). Avec un texte : l'API filtre et trie les premiers résultats (une
  recherche filtrée ne renvoie pas de personnes). « Tout » = une rangée Films et une rangée
  Séries ; un type choisi = une grille qui charge la page suivante en arrivant à la fin
  (`_PagedGrid`). Téléphone : pas de carrousel ni de grande image (demande du développeur) ;
  grand écran : la grande image (`catalog/hero.dart`, partagée avec l'accueil) montre le premier
  résultat, puis suit la carte sélectionnée ou survolée. Un genre absent du type choisi est
  retiré. Recherches récentes synchronisées entre les appareils du profil
  (`RecentSearches`, API `/profiles/{id}/searches`) : affichées tout de suite, enregistrées en
  arrière-plan, 8 visibles sur 20 gardées ; « orbi » puis « orbite » ne garde que « orbite » (même
  règle que l'API). Pas de page par genre : on filtre par genre dans la recherche.
- **Fiche : « Créateur et distribution »** : la rangée commence, à gauche, par la réalisation
  (film, `directors`) ou la création (série, `creators`), marquées « Réalisation » / « Création »
  (mots neutres), puis la distribution ; « Distribution » seul si TMDb n'en donne pas. Pas de
  ligne « Avec … · Réalisation : … » sous le résumé (demande du développeur). Les cartes
  de personnes passent toutes par `PersonCard` (`catalog/widgets.dart`, fiche et recherche) : nom
  et rôle sur deux lignes au plus, pour ne pas les couper.
- **Logo du titre** (`TitleLogo`, `catalog/widgets.dart`) : fiche, grande image (accueil et
  recherche) et carrousel du téléphone écrivent le titre avec le logo TMDb (`logo_url`),
  dimensionné avant son chargement (`logo_aspect_ratio`) ; sans logo, ou s'il ne se charge pas, le
  nom est écrit. L'accueil donne le logo avec chaque titre (logo tout de suite) ; ailleurs
  (recherche, « Continuer à regarder »), il vient de la fiche quand la sélection s'arrête, dans une
  place de hauteur fixe (rien ne bouge). Carrousel du téléphone : l'affiche sans texte
  (`MediaItem.cleanPoster`, `textless_poster_url` de l'accueil), sinon l'affiche habituelle. Fond de
  la fiche : l'image sans texte
  (`textless_backdrop_url`, via `TitleDetails.background(size)`), sinon `backdrop_url`. Le lecteur
  d'écran lit toujours le nom.
- **Lecture et sous-titres** (`/profil/lecture`, `PlaybackSettingsScreen`, API :
  `vixeo_backend/docs/lecture.md`) : langue audio préférée (null = version originale), langue des
  sous-titres (null = désactivés ; noms dans `profiles/languages.dart`, mêmes codes que l'API) et
  « Passer automatiquement » le générique de début, le résumé, le générique de fin, l'aperçu
  (sinon le lecteur montrera un bouton « Passer »). Champs du profil : synchronisés, pas de PIN
  parental. Le lecteur n'existe pas encore : `features/playback` (`PlaybackRepository`,
  `SkipSegments.at`, `SkipKind.autoFor`) prépare ce qu'il utilisera. Les applis ne parlent jamais
  à OpenSubtitles ni à TheIntroDB : tout passe par l'API (clé Vixeo commune).
- **Pas de section « Sources »** sur la fiche (demande du développeur).
- **Format des affiches** : réglage du profil (`poster_format` : vertical par défaut, ou
  horizontal 16:9), appliqué par `PosterRow` / `PosterGrid`. **Pas de nom sur les affiches**, dans
  les deux formats (demande du développeur : l'image suffit) ; le nom n'est écrit que pour un titre
  sans aucune image, et reste dans le libellé pour les lecteurs d'écran.
- **Avatars** : galerie `GET /avatars` regroupée par licence (`features/profiles/avatars.dart`,
  pixel art dessiné par `PixelAvatarPainter`, ou `image_url`) ; `ProfileAvatar` partout où le
  profil apparaît. Uniquement des avatars originaux, ou de licences dont on a les droits.
- **Images** : `NetImage` (cache, couleur de remplacement). Tailles TMDb via
  `MediaItem.poster('w780')` / `backdrop('original')`, dérivées des URL renvoyées par l'API.
- Tests : `flutter test` ne charge pas les polices (texte de remplacement), sans réseau.

## Branches

- Le travail se fait **directement sur `main`** (demande du développeur).

## État actuel

- Fait : connexion, inscription, session persistante (jeton chiffré), connexion TV par QR code
  (validée depuis le téléphone), « Qui regarde ? » (PIN de profil, ajout avec PIN parental si
  activé), accueil (carrousel / grande image, « Continuer à regarder », rangées), Films / Séries,
  fiche film et série (saisons, épisodes, distribution, recommandations, bande-annonce, Ma liste,
  Vu), page personne (`/personne/:id` : biographie, « Connu pour », filmographie ; ouverte depuis
  la distribution et la recherche), recherche (« Explorer », filtres type / genre / années /
  note, tri, grande image sur grand écran, résultats groupés, recherches récentes synchronisées),
  Ma liste, « Mon profil » (avatar par licence, format des affiches, lecture et sous-titres,
  contrôle parental, connecter une TV, changer de profil,
  déconnexion, mon compte : export et suppression, appareils connectés), mot de passe oublié,
  politique de confidentialité et « Aide et à propos », vérification des
  mises à jour (Android / iOS), mises en page téléphone et TV / grand écran, navigation à la
  télécommande.
- Notarisation Apple : audit et état des corrections dans `APPLE_NOTARIZATION.md`.
- Vérifié de bout en bout (web) contre l'API Laravel locale avec un faux TMDb.
- Pas encore fait : lecteur vidéo et sources (Jellyfin / Plex / Emby), qui utilisera les réglages
  de lecture, les moments à passer et les sous-titres déjà prêts ; déploiement web (workflow
  `deploy-web.yml` du §8.2).
- Limite connue : sur le web avec le mode lecteur d'écran activé, le focus initial et les flèches
  passent par le navigateur (Tab fonctionne). Sans lecteur d'écran, et sur Android TV, les flèches
  et OK fonctionnent.

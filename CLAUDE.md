# Vixeo — appli Flutter (vixeo_frontend)

Appli **Vixeo** (media center) pour le web, Android, Android TV / Google TV et iOS, avec une
seule base de code. L'API Laravel est dans
[`davybrieu/vixeo_backend`](https://github.com/davybrieu/vixeo_backend).

**Charte graphique : [`docs/charte-graphique.md`](docs/charte-graphique.md)** (couleurs, textes,
espacements, composants, focus) : à suivre pour tout écran ; valeurs dans `core/theme.dart` et
`core/design.dart`.

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
    account/     Mon compte (export, suppression), appareils connectés
    updates/     vérification des mises à jour Android / iOS (UpdateGate, écrans)
    profiles/    « Qui regarde ? », PIN, ajout, « Mon profil », avatars, contrôle parental
    catalog/     modèles TMDb, accueil, fiche film / série, page personne, cartes et rangées
    library/     synchro par profil (Ma liste, vus, « Continuer à regarder »), page Ma liste
    search/      recherche : « Explorer » sans texte, filtres (type, genre, années, note) et tri,
                 recherches récentes synchronisées (search_history.dart)
    playback/    pour le futur lecteur : moments à passer (TheIntroDB) et sous-titres (OpenSubtitles),
                 via l'API
    tv/          TV en direct : chaînes et catégories de l'API (rangée, grille de la recherche),
                 lecteur d'un flux (HLS) ; pas de page à part
    shell/       navigation : onglets en bas (téléphone), rail à gauche (TV, tablette, ordi)
    tmdb/        compte TMDb du profil (page Connexions, QR code), notes et commentaires (fenêtre,
                 boutons, onglet « Avis »)
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
  `/mot-de-passe-oublie` est une page de connexion.
- **Connexion TV par QR code** (`features/auth/device_login.dart`, API : `vixeo_backend/docs/connexion-tv.md`) :
  sur grand écran, la page de connexion affiche `TvCodeCard` (QR code vers `<WEB_URL>/tv?code=…`
  + code court), qui interroge `/auth/device/token` toutes les `interval` secondes et demande un
  nouveau code sur un 410. Le téléphone valide sur `/tv` (« Mon profil » → « Connecter une TV »).
  Le `device_code` reste en mémoire, jamais dans une URL.
- **TV en direct** (`features/tv`, API : `vixeo_backend/docs/tv-direct.md`) : **pas de page « TV »
  ni d'onglet** (supprimés, demande du développeur ; `/tv-live` redirige vers `/recherche`). Les
  chaînes sont sur l'accueil (**quatre rangées** « Chaînes TV généralistes », « … sport »,
  « … info », « … enfants », demande du développeur : `channelSections` classe les chaînes selon le
  nom de leur catégorie, mots-clés sans accents, 24 par rangée, rangée vide masquée ; aucune
  correspondance → une seule rangée « Chaînes TV » ; `ChannelRow` **sans « Voir tout »** ; test
  `test/home_channels_test.dart`) et dans la recherche
  (type « Chaînes TV » : grille `ChannelSearchResults`, filtre « Catégorie » de `/tv/categories`,
  même bouton `FilterChipButton` que « Genre » ; section « Chaînes TV » de « Tout »). Une chaîne
  passe toujours par `ChannelTile` (focus télécommande). **Logo** : l'URL `logo` de l'API, sur notre
  domaine (`/tv/logo/{hash}` : l'API relaie l'image du fournisseur sans la stocker, gardée 7 jours
  par l'appli et le navigateur) ; sur le web, `Image.network(webHtmlElementStrategy:
  WebHtmlElementStrategy.prefer)` (balise `<img>`) ; `http://` passé en `https://` par
  `TvChannel.fromJson` ; sans logo, une icône ; **toucher une chaîne ouvre sa page**
  (`ChannelScreen`, `/chaine/:id`, `openChannel`, demande du développeur ; comme une fiche film /
  série) : logo, nom, catégorie,
  « EN DIRECT », « Regarder » (focus à l'arrivée), « En ce moment » (titre,
  heures, barre de progression, résumé) et le **programme** (EPG, `/tv/channels/{id}/epg`,
  `tvGuideProvider` ; heures locales, « Demain 08:30 » ; un appui montre le résumé complet ; mis à
  jour toutes les 30 s ; sans guide sur le serveur : « Le programme n’est pas disponible pour le
  moment. »). Test : `test/channel_screen_test.dart`. « Regarder »
  ouvre tout de suite `PlayerScreen.live` **en plein écran, sur le navigateur racine** (`playLiveChannel`,
  `rootNavigator: true` : ni rail ni barre d'onglets par-dessus), qui demande son flux (`/tv/channels/{id}/stream`) sous
  le même indicateur que le début de la lecture (un seul chargement, pas de fenêtre avant). Lecteur : le même que pour
  les films et séries (`features/playback/player_screen.dart`, `LivePlayerScreen` n'en est qu'une entrée) ;
  boutons ronds `VxIconAction` / `VxFocusable` avec un libellé pour les lecteurs d'écran (les tests les cherchent par
  ce libellé : pas d'`IconButton` à infobulle). Contrôles en surimpression (retour, nom de la chaîne, « EN DIRECT » ; lecture / pause, son et
  volume (souris), « Revenir au direct », plein écran sauf
  sur TV : `fullscreen/`), masqués après 4 s de lecture, rappelés par un appui, la souris ou une
  touche (la première touche de la télécommande ne fait que les montrer) ; raccourcis K, M, F et
  touches média. **Un seul flux par chaîne** (`url`), pas de choix de source ni de passage
  à une autre source (demande du développeur). Un flux qui refuse de démarrer, ou dont l'image ne
  bouge pas pendant 15 s (`stallTimeout`), affiche « Impossible de lire cette chaîne. » et
  « Réessayer » (une seule fois par échec). Sur le web,
  un flux que le navigateur ne sait pas décoder (H.265…) fait échouer hls.js, mais
  `video_player_web_hls` ne sait pas lire cette erreur et l'écran restait noir. Le lecteur lit
  donc la position réelle (`controller.position`, pas `value.position`, figée pour un direct) ;
  tant que l'image ne bouge pas, les contrôles et un indicateur restent affichés. Test : `test/live_player_test.dart`. L'API renvoie une URL sur **notre
  propre origine** (un proxy signé, jamais l'adresse du fournisseur) ; `TvStream.headers` reste
  vide et est tout de même transmis au lecteur. Sur le web, les navigateurs autres que Safari ne
  lisent pas le HLS : `web/hls.min.js` (hls.js, Apache-2.0, servi depuis notre origine, licence
  dans « Licences ») est chargé par `web/index.html` et le plugin `video_player_web_hls` s'en sert
  pour les flux HLS. Android / iOS / Safari lisent le HLS nativement. Test : `test/web_hls_test.dart`.
- **Contrôle parental** : deux pages séparées dans « Mon profil » (demande du développeur).
  « Contrôle parental » (`parental_control_screen.dart`, `/profil/controle-parental`) : les
  restrictions de chaque profil (profil enfant, âge maximum, titres sans classification) ; sans
  code, une carte invite à en définir un. « Code PIN » (`parental_pin.dart`, `/profil/code-pin`) :
  activer, changer ou désactiver le code PIN parental. Les deux passent par `ParentalPinPage` : si
  un PIN parental existe, il est demandé à l'arrivée (`ParentalPinGate`), gardé en mémoire tant
  que la page est ouverte et envoyé (`parental_pin` / `current_pin`) avec chaque modification ;
  « Code oublié ? » désactive le contrôle avec le mot de passe du compte. Après une modification
  de restriction : invalider `profilesProvider` et `homeProvider` (le catalogue dépend des limites).
- **Mises à jour** (`features/updates`, API : `vixeo_backend/docs/mise-a-jour.md`) : sur Android et
  iOS, `UpdateGate` (dans le `builder` de `MaterialApp.router`) interroge `GET /app/update` avec le
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
  confirmation ; la progression est partagée (`updateDownloadProvider`). Sans APK, ou sur iOS, le
  bouton ouvre la page d'installation du site. L'appli ne
  charge jamais de code qu'elle exécuterait elle-même. Publication : `docs/android-release.md`. Le web ne vérifie pas. Pour essayer dans un navigateur :
  version « profile » avec `--dart-define=UPDATE_PLATFORM=android`.
- **Version et signature** : `version: x.y.z+build` dans `pubspec.yaml` (`x.y.z` : version
  affichée). Les APK de la CI prennent comme build le numéro du run (`--build-number`), toujours
  croissant ; un APK compilé à la main doit avoir un build plus grand que le dernier publié. La version Release est signée avec la clé de release
  (`android/key.properties` ou variables `VIXEO_KEYSTORE_*`, jamais dans le dépôt) ; sans clé, le
  build Release échoue. La CI publie chaque APK en release GitHub `android-<build>` (APK et
  SHA-256), **seule source** des mises à jour pour l'API (plus de commande `vixeo:release`) ;
  `[obligatoire]` dans le titre de la release impose la mise à jour. Pas d'appli iOS pour
  l'instant (l'API répond « à jour » pour iOS). Détails : `docs/android-release.md`.
- **Chargement au démarrage** (demande du développeur : un seul chargement) : `web/index.html`
  n'affiche rien avant Flutter (fond sombre seulement, pas d'écran HTML). Ensuite, un seul
  chargement : `AppLoading` (`core/widgets/app_loading.dart`, logo + cercle), affiché par
  l'écran de démarrage (`/demarrage`), par « Qui regarde ? » tant que les profils chargent et par
  `AppShell` au premier chargement de l'accueil (sans la navigation, une seule fois par lancement).
  La carte TV de la connexion montre une forme vide, pas de cercle, en attendant son code. Ne pas
  ajouter d'autre indicateur au démarrage. Test : `test/app_loading_test.dart`.
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
    `VxFocusable` ne vole jamais le focus à un élément du même écran ou de la même fenêtre (champ
    de texte…), mais une fenêtre (choix, confirmation) le prend même si la page dessous l'avait ;
  - barre de mise à jour : flèche Haut en haut d'une page (rien au-dessus) → bouton « Télécharger »,
    flèche Bas → retour à l'élément de la page ; jamais depuis une fenêtre ou un menu ;
  - seul ce qui se presse prend le focus (`VxFocusable` sans `onPressed` ni `onLongPress` : non
    focalisable ; `InfoSection` est du texte simple) ;
  - touche Retour (`BackNavigationGuard`) : d'une sous-page vers l'accueil (ou vers la connexion
    depuis l'inscription et le mot de passe oublié) ; depuis l'accueil, la connexion ou
    « Qui regarde ? », confirmation avant de quitter l'appli ;
  - les tailles TV sont celles du design 1920×1080, converties avec `Layout.of(context).tv(px)` ;
  - les rangées horizontales sont dans un `FocusTraversalGroup` ;
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
- **Transition entre les pages** (demande du développeur) : chaque nouvelle page apparaît en
  **fondu** (300 ms, `vxPageFade`), sans glissement, et repart en fondu au retour. Le thème le
  règle pour toutes les plateformes (`pageTransitionsTheme` → `VxFadePageTransitionsBuilder`,
  `core/theme.dart`) : cela vaut pour toute route `builder:` de go_router et tout
  `MaterialPageRoute`. Les pages principales (onglets) passent par `tab(state, …)` dans
  `router.dart` (`CustomTransitionPage` avec le même fondu). Ne pas ajouter d'autre transition.
- **Rangées de l'accueil : « Voir tout »** (demande du développeur) : à droite du titre de chaque
  rangée, un bouton rond à flèche (`SectionHeader(onSeeAll:)`) ouvre la liste entière
  (`TitleListScreen`, `catalog/list_screen.dart`, `/liste/:type/:list?titre=…`) : bouton retour,
  titre de la rangée, grille qui charge la page suivante en arrivant à la fin (`PagedGrid`, le
  même que la recherche ; API `/catalog/{type}/lists/{list}`, `titleListProvider`).
- **Page « Chaînes TV »** (`/chaines-tv`, `TvChannelsScreen` ; demande du développeur : comme
  l'accueil) : une **rangée par catégorie** (`channelCategorySections`, `tvChannelRowsProvider` :
  catégories et chaînes demandées une fois, 24 chaînes par rangée, catégorie vide masquée), avec
  le bouton rond « Voir tout » qui ouvre toute la catégorie (`TvCategoryScreen`,
  `/chaines-tv/categorie/:id?titre=…` : bouton retour, nom de la catégorie, grille
  `ChannelSearchResults`). **Ni champ de recherche ni filtre de catégorie sur cette page**
  (supprimés, demande du développeur) : on cherche une chaîne dans la recherche. Toutes les
  catégories qui ont des chaînes ont leur rangée.
- **Rail de navigation sur un écran bas** : icônes et marges rétrécissent selon la hauteur
  (40 au minimum), puis le rail défile avec une barre (`_Rail`, `shell/app_shell.dart`). Test :
  `test/profile_features_test.dart`.
- **Pas de pages « Films » ni « Séries »** (supprimées, demande du développeur) : ni route, ni
  onglet, ni entrée du rail ; `/films` et `/series` redirigent vers `/accueil`. `HomeScreen` et
  `homeProvider` n'ont plus de paramètre `type`. Pour ne voir que les films ou les séries : le
  filtre de type de la recherche. Ne pas les réintroduire.
- **Pas de « Favoris » ❤** (supprimés, demande du développeur ; supprimés aussi de l'API, groupe
  `liked`) : ni page `/favoris`, ni onglet, ni bouton cœur sur les titres, les épisodes ou les
  chaînes. « Ma liste » (`favorite`) reste. Ne pas les réintroduire.
- **Actions sur un titre** (Ma liste, Vu / non vu, Noter, Bande-annonce) : toujours le même bouton
  rond **icône seule** (`VxIconAction`, `FavoriteButton`, `WatchedButton`, `RateTitleButton`), sans
  texte visible (libellé pour les lecteurs d'écran uniquement). Le même bouton ajoute et retire.
  Chaque action se confirme par une alerte (`showVxSnack`) : « Ajouté à votre liste », « Supprimé
  de votre liste », « Marqué comme vu », « Marqué comme non vu » (`features/library/actions.dart`),
  « Note enregistrée : 8/10 », « Note supprimée ».
- **Compte TMDb, notes et avis** (`features/tmdb`, API : `vixeo_backend/docs/compte-tmdb.md`) :
  chaque profil peut lier un compte TMDb dans « Mon profil » → **Connexions**
  (`/profil/connexions`, `ConnectionsScreen` ; pas de section TMDb ni « Mes notes » dans les
  paramètres, demande du développeur) ; le même compte TMDb peut être lié à plusieurs profils,
  même d'autres comptes Vixeo. Liaison : la page d'autorisation de TMDb s'ouvre (téléphone,
  ordinateur) ou s'affiche en QR code (grand écran), et la page interroge `link/complete` toutes les
  5 s (et au retour au premier plan) ; « Changer de compte », « Déconnecter » (supprime les
  commentaires). Une fois lié : bouton « Noter » sur la fiche (film, série) et étoile en haut à
  droite de l'image de chaque épisode (« Ma note : 8/10 » en bas de l'image), seulement si un
  compte est lié (`canRateProvider`) ;
  fenêtre `showRatingDialog` (10 étoiles par demi-points ; télécommande : ← →, chiffres, OK ;
  **commentaire facultatif**, gardé par Vixeo, jamais envoyé à TMDb). **« Avis »** est un onglet de
  la navigation (`/avis`, `ReviewsScreen`) : en-tête commun avec recherche (titre, épisode,
  commentaire, sans accents ni casse), filtres Tout (par défaut) / Films / Séries / Épisodes, la
  plus récente d'abord. Chaque avis montre ses étoiles (`StarRow`) et **aucun bouton** (demande
  du développeur) : un appui ouvre « Mon avis » (`ReviewScreen`, `/avis/movie/550`,
  `/avis/tv/1399?saison=1&episode=2`), où l'on change les étoiles et le commentaire (`RatingForm`,
  le même formulaire que la fenêtre de note) ; « Enregistrer » et « Supprimer l’avis »
  (confirmation) ramènent à la liste, « Voir la fiche » ouvre le titre. Toutes les notes sont chargées d'un coup
  (`reviewsProvider`). Toute écriture passe par `TmdbRatings`, qui rafraîchit la fiche, les
  épisodes et « Avis ». L'API de TMDb n'accepte que des notes (0,5 à 10). 409 de l'API → plus de
  compte lié (`TmdbAccountController.lost`). Anciennes adresses `/profil/tmdb` et `/profil/notes`
  redirigées.
- **Note TMDb** : la note moyenne de TMDb s'affiche partout avec `TmdbRating` (étoile, note, petit
  logo officiel TMDb `assets/images/tmdb_short.png`, « Primary short » de themoviedb.org converti
  en PNG sans modification). Pas de page de confidentialité ni de mention TMDb dans l'appli
  (décision du développeur).
- **Recherche** (`features/search`, API : filtres de `/catalog/{type}/discover` et `/catalog/search`) :
  barre de filtres `SearchFilterBar` (Tout / Films / Séries / Chaînes TV / Personnes, genre,
  années, note minimale, tri ; « Catégorie » pour les chaînes) ; `SearchFilters` donne les
  paramètres de l'API. **« Chaînes TV » et « Personnes » toujours proposés**, avec ou sans texte
  (demande du développeur) : dans « Tout », après Films et Séries, une section « Chaînes TV » et
  une section « Personnes » toujours affichées (une ligne « Aucune … » si vide ; masquées avec un
  filtre genre / années / note, qui ne s'applique qu'aux titres). Sans texte, « Personnes » = les
  personnes populaires (`/catalog/people/popular`). Sans texte : « Explorer » tout le catalogue
  (`/discover`, tri par popularité par défaut ; « Pertinence » n'existe qu'avec un texte).
  « Ma liste » reprend la barre sans « Personnes » ni « Catégorie » (`kinds`, `channelCategories`). Avec un texte : l'API filtre et trie les premiers résultats (une
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
  (sinon le lecteur montrera un bouton « Passer »). Champs du profil : synchronisés, pas de PIN
  parental. Le lecteur n'existe pas encore : `features/playback` (`PlaybackRepository`,
  `SkipSegments.at`, `SkipKind.autoFor`) prépare ce qu'il utilisera. Les applis ne parlent jamais
  à OpenSubtitles ni à TheIntroDB : tout passe par l'API (clé Vixeo commune).
- **Pas de section « Sources »** sur la fiche (demande du développeur).
- **Épisodes d'une série** (`_Episodes`, `_EpisodeCard`, `catalog/details_screen.dart` ; demande
  du développeur) : sous les puces des saisons, une **rangée horizontale** de grandes cartes
  (largeur 300 téléphone, 340 tablette, 520 TV) qui défile de gauche à droite. Carte : image 16:9
  avec le badge « Épisode 3 » en haut à gauche, puis le titre (1 ligne), le résumé (**3 lignes au
  plus**, place toujours réservée) et, sur la dernière ligne, la durée puis la note TMDb à gauche
  et la date de diffusion à droite. Hauteur de carte fixe (`_EpisodeCard.heightOf`, suit la
  taille du texte du système). Changer de saison revient au premier épisode. Test :
  `test/details_people_test.dart`.
- **Format des affiches** : réglage du profil (`poster_format` : vertical par défaut, ou
  horizontal 16:9), appliqué par `PosterRow` / `PosterGrid`. **Sur téléphone** (demande du
  développeur), sous chaque affiche : le titre sur une ligne, puis l'année à gauche et la note
  TMDb avec son logo à droite (`PosterCard`, hauteur `PosterCard.captionHeightOf(context)`, que
  les rangées et les grilles ajoutent à l'image ; grilles : `posterGridDelegate(…,
  captionHeight:)`). **Tablette et TV : pas de nom sur les affiches**, dans les deux formats
  (l'image suffit) ; le nom n'est écrit que pour un titre sans aucune image, et reste dans le
  libellé pour les lecteurs d'écran. En horizontal, le logo du
  titre s'affiche quand le titre le donne (rangées de l'accueil) : **jamais de requête de fiche par
  carte** (`titleProvider` dans `PosterCard` = une requête par titre affiché, au-delà de la limite
  de l'API). « Ma liste » demande tous ses titres en une requête (`titlesByIdProvider`, API
  `/catalog/titles`). Sur une carte horizontale, le logo est demandé en w300 (`cardLogoUrl`) et
  apparaît avec l'image (`ImagesTogether` : les deux une fois chargées), jamais après. Badge « Ma
  liste » sur l'affiche, « vu » dans le libellé. Titre de rangée et lien « Voir tout » :
  `SectionHeader(title, onSeeAll: …)`. Pages principales (Recherche, Ma liste, Avis) : même en-tête
  `VxPageHeader` (titre, recherche, `FilterBar`) et `pageContentPadding` (charte, § 6).
- **Avatars** : galerie `GET /avatars` regroupée par licence (`features/profiles/avatars.dart`,
  pixel art dessiné par `PixelAvatarPainter`, ou `image_url`) ; `ProfileAvatar` partout où le
  profil apparaît. Uniquement des avatars originaux, ou de licences dont on a les droits. Chaque
  nouveau profil (y compris celui créé à l'inscription) reçoit un avatar du catalogue au hasard
  (côté API) ; la page « Choisir un avatar » ne propose que des avatars, plus de choix « Initiale »
  (demande du développeur). Choisir un avatar l'enregistre et **reste sur la page** (pas de
  retour en arrière, demande du développeur). L'initiale reste affichée pour un ancien profil sans
  avatar. La tuile « Avatar » des paramètres n'écrit pas le nom du profil.
- **Espacements** (charte, § 5) : les écarts d'une page ont un nom dans `core/design.dart`
  (`layout.sectionGap`, `titleGap`, `introGap`, `listGap`, `cardGap`) et le bas d'une page qui
  défile passe par `pageBottomPadding(context)` (place de la barre d'onglets comprise). Pages
  secondaires : `InfoPage` / `InfoBody`, `InfoIntro`, `InfoSection`, `VxCard`, tout aligné sur
  la colonne (pas de retrait). « Paramètres » (onglet) a le `VxPageHeader` des pages
  principales. Paramètres du profil : chaque groupe passe par `_Section`
  (`profile_preferences_screen.dart`). Tests : `test/design_test.dart`.
- **Logo** (`brand/README.md`) : V blanc, triangle vert, « Vixeo » en Sora ExtraBold, couleurs
  de la charte, **le même partout** (demande du développeur) : `VxLogo` dans l'appli (mêmes
  formes que `brand/vixeo-logo.svg`), favicon et icônes web (`web/`), icône Android adaptative
  (`mipmap-anydpi-v26`, `drawable/ic_launcher_foreground.xml`) et PNG d'avant Android 8, bannière
  Android TV (`drawable/tv_banner.xml`), icônes iOS (`AppIcon.appiconset`), site (`vixeo_web`) et
  favicon de l'API. Tout est généré par `brand/tools` : changer le logo là, puis recopier.
- **Images** : `NetImage` (cache, couleur de remplacement). Tailles TMDb via
  `MediaItem.poster('w780')` / `backdrop('original')`, dérivées des URL renvoyées par l'API.
- Tests : `flutter test` ne charge pas les polices (texte de remplacement), sans réseau.
- **CI** (`.github/workflows/build-web.yml`) : `flutter analyze` (les erreurs bloquent) et
  `flutter test` d'abord ; puis compilation web (commitée dans `build/web`, déploiement Forge) et
  APK signé publié en release GitHub `android-<n>` (lue par l'API pour les mises à jour). Couleurs
  des actions destructives : `VxColors.danger` / `dangerText`, `VxButtonKind.danger`.

## Branches

- Le travail se fait **directement sur `main`** (demande du développeur).

## État actuel

- Fait : connexion, inscription, session persistante (jeton chiffré), connexion TV par QR code
  (validée depuis le téléphone), « Qui regarde ? » (PIN de profil, ajout avec PIN parental si
  activé), accueil (carrousel / grande image, « Continuer à regarder », rangées),
  fiche film et série (saisons, épisodes avec date de diffusion, distribution, recommandations,
  bande-annonce, Ma liste, Vu, notes TMDb du film, de la série et des épisodes), page personne (`/personne/:id` : biographie, « Connu pour », filmographie ; ouverte depuis
  la distribution et la recherche), recherche (« Explorer », filtres type / genre / années /
  note, tri, grande image sur grand écran, résultats groupés, recherches récentes synchronisées),
  Ma liste, « Avis » (notes TMDb et commentaires), « Mon profil » (avatar par licence, paramètres
  d’apparence, No spoil, langues et lecture automatique, contrôle parental et code PIN (deux pages),
  connecter une TV, changer de profil, Connexions (TMDb),
  déconnexion, mon compte : export et suppression, appareils connectés), mot de passe oublié,
  vérification des
  mises à jour (Android / iOS), TV en direct (catégories, chaînes, lecture du flux ; HLS sur le
  web via hls.js), mises en page téléphone et TV / grand écran, navigation à la
  télécommande.
- Notarisation Apple : audit et état des corrections dans `APPLE_NOTARIZATION.md`.
- Vérifié de bout en bout (web) contre l'API Laravel locale avec un faux TMDb.
- Pas encore fait : lecteur vidéo et sources (Jellyfin / Plex / Emby), qui utilisera les réglages
  de lecture, les moments à passer et les sous-titres déjà prêts ; déploiement web (workflow
  `deploy-web.yml` du §8.2).
- Limite connue : sur le web avec le mode lecteur d'écran activé, le focus initial et les flèches
  passent par le navigateur (Tab fonctionne). Sans lecteur d'écran, et sur Android TV, les flèches
  et OK fonctionnent.

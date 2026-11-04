# Vixeo — appli Flutter (vixeo_frontend)

Appli **Vixeo** (media center) pour le web, Android, Android TV / Google TV et iOS, avec une
seule base de code. L'API Laravel est dans
[`davybrieu/vixeo_backend`](https://github.com/davybrieu/vixeo_backend).

**Lire d'abord [`docs/CONTEXT.md`](docs/CONTEXT.md)** (copie de celui de l'API) : décisions produit,
périmètre légal (§3 : ce qui est hors périmètre ne doit pas être implémenté), sécurité (§6).

**Écarté par le développeur** (ne pas proposer) : import IPTV / M3U / Xtream, radio, replays.

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
flutter build web --release --dart-define=API_URL=https://api.<domaine>
```

Dans un conteneur Claude Code cloud, Flutter n'est pas préinstallé : voir le script de
`docs/CONTEXT.md` §7 (clone du canal stable dans `/opt/flutter`). Pas de SDK Android ni de
Xcode : seules les cibles web et les tests se vérifient dans le conteneur.

## Structure

```
lib/
  main.dart, app.dart, router.dart   entrée, thème, raccourcis télécommande, routes
  core/
    config.dart                      API_URL (--dart-define)
    theme.dart                       couleurs (VxColors), polices Sora / Inter (VxText)
    device/layout.dart               téléphone / tablette / grand écran, détection TV, échelle TV
    api/                             client HTTP (dio), erreurs en français, stockage du jeton
    widgets/                         VxFocusable (focus TV), boutons, images, états vides / erreur
  features/
    auth/        connexion (page d'accueil de l'appli), inscription, session
    profiles/    « Qui regarde ? », PIN, ajout, « Mon profil », avatars
    catalog/     modèles TMDb, accueil, fiche film / série, cartes et rangées
    library/     synchro par profil (favoris, vus, « Continuer à regarder »), Ma liste
    search/      recherche, genres
    shell/       navigation : onglets en bas (téléphone), rail à gauche (TV, tablette, ordi)
```

## Conventions

- **État** : Riverpod 3 (`Provider`, `FutureProvider.family`, `Notifier`, `AsyncNotifier`), sans
  génération de code. Les providers du catalogue surveillent le profil actif : changer de profil
  recharge les données (l'API filtre selon l'âge du profil).
- **Navigation** : go_router. La connexion est la page d'entrée ; le routeur redirige vers
  `/connexion` tant qu'on n'est pas connecté, puis vers `/profils` tant qu'aucun profil n'est choisi.
  Le routeur n'écoute que le statut de connexion et la présence d'un profil : modifier le profil
  (avatar…) ne doit pas reconstruire les pages.
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
  - les rangées horizontales sont dans un `FocusTraversalGroup`.
- **Actions sur un titre** (Ma liste, Vu / non vu, Bande-annonce) : toujours le même bouton
  rond **icône seule** (`VxIconAction`, `FavoriteButton`, `WatchedButton`), sans texte visible
  (libellé pour les lecteurs d'écran uniquement). Le même bouton ajoute et retire. Chaque action
  se confirme par une alerte (`showVxSnack`) : « Ajouté à votre liste », « Supprimé de votre
  liste », « Marqué comme vu », « Marqué comme non vu » (`features/library/actions.dart`).
- **Pas de section « Sources »** sur la fiche (demande du développeur).
- **Format des affiches** : réglage du profil (`poster_format` : vertical par défaut, ou
  horizontal 16:9 avec le titre sur l'image), appliqué par `PosterRow` / `PosterGrid`.
- **Avatars** : galerie `GET /avatars` regroupée par licence (`features/profiles/avatars.dart`,
  pixel art dessiné par `PixelAvatarPainter`, ou `image_url`) ; `ProfileAvatar` partout où le
  profil apparaît. Uniquement des avatars originaux, ou de licences dont on a les droits.
- **Images** : `NetImage` (cache, couleur de remplacement). Tailles TMDb via
  `MediaItem.poster('w780')` / `backdrop('original')`, dérivées des URL renvoyées par l'API.
- Tests : `VxFonts.useGoogleFonts = false` dans les tests de widgets (pas de réseau).

## Branches

- Le travail se fait **directement sur `main`** (demande du développeur).

## État actuel

- Fait : connexion, inscription, session persistante (jeton chiffré), « Qui regarde ? » (PIN de
  profil, ajout avec PIN parental si activé), accueil (carrousel / grande image, « Continuer à
  regarder », rangées), Films / Séries, fiche film et série (saisons, épisodes, distribution,
  recommandations, bande-annonce, Ma liste, Vu), recherche (genres, résultats groupés), Ma liste,
  « Mon profil » (avatar par licence, format des affiches, changer de profil, déconnexion),
  mises en page téléphone et TV / grand écran, navigation à la télécommande.
- Vérifié de bout en bout (web) contre l'API Laravel locale avec un faux TMDb.
- Pas encore fait : lecteur vidéo et sources (Jellyfin / Plex / Emby), connexion TV par QR code
  (route d'API à créer), réglages du contrôle parental dans l'appli, historique de recherche
  synchronisé, page personne (filmographie), déploiement web (workflow `deploy-web.yml` du §8.2).
- Limite connue : sur le web avec le mode lecteur d'écran activé, le focus initial et les flèches
  passent par le navigateur (Tab fonctionne). Sans lecteur d'écran, et sur Android TV, les flèches
  et OK fonctionnent.

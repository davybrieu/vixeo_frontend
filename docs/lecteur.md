# Lecteur vidéo : architecture multiplateforme

Un seul écran (`PlayerScreen`, `lib/features/playback/player_screen.dart`) et une seule interface
de commandes Flutter, sur toutes les plateformes. Seul le **moteur de lecture** change.

| Plateforme | Moteur | Paquet | Ce qui lit réellement |
|---|---|---|---|
| Android (téléphone, tablette, Android TV) | `NativePlayerEngine` | `better_native_video_player` | ExoPlayer (Media3) |
| iOS (plus tard) | `NativePlayerEngine` | `better_native_video_player` | AVPlayer |
| Windows (10 et 11, 64 bits) | `MediaKitPlayerEngine` | `media_kit`, `media_kit_video`, `media_kit_libs_windows_video` | libmpv (FFmpeg) |
| Tests, autres ordinateurs | `VideoPlayerEngine` | `video_player` | selon la plateforme |

**Plus de version web** (demande du développeur, 20/11/2026) : ni `<video>` HTML5, ni hls.js, ni
problème de CORS. Les applis lisent les flux directement, avec les en-têtes HTTP que donne la
source (`Referer`, `User-Agent`…).

## Commandes (demande du développeur, d'après un autre lecteur)

Les mêmes sur toutes les plateformes, par-dessus l'image :

- **en haut à gauche**, le bouton retour, le même et à la même place que sur les autres pages
  (`VxBackButton`) ; **en haut à droite**, « EN DIRECT » pendant qu'une chaîne joue ;
- **au milieu**, reculer de 10 s, lecture / pause (un cercle de chargement à sa place tant qu'il
  n'y a pas d'image), avancer de 10 s ; lecture / pause seulement pour une chaîne. Toujours
  blancs, jamais grisés (invisibles sur une image sombre) ; tant qu'aucune source n'est choisie,
  lecture ouvre les sources. Touches : J / L et les touches retour rapide / avance rapide d'une
  télécommande ;
- **en bas à gauche**, ce qui joue : le titre, l'année (film) ou « Saison 1 · Épisode 2 · nom »
  (série), puis « Via » le fournisseur de la source, un éclair et le nom du lien ; dessous, la
  barre de progression, **toujours là pour un titre** (à 0, immobile, avant la vidéo) ;
- **en bas**, les icônes à gauche (blanches, sans fond, petites : 40 sur téléphone) : sous-titres,
  son, sources, **cadrage**, épisodes, épisode suivant, plein écran ; pour une chaîne : son,
  « Revenir au direct », cadrage, plein écran. **Pas de lecteur externe** (demande du
  développeur). Trop d'icônes pour la largeur : la rangée **défile de gauche à droite** (doigt,
  souris, ou focus de la télécommande), jamais sous le temps ; pas de flèche. Le temps
  « 00:02 / 2:52:35 » est à droite (« 00:00 / 00:00 » avant la vidéo). Le curseur de volume
  n'existe qu'avec une souris (Windows), pas sur Android ni iOS.
- **Cadrage** (un appui passe au suivant, une alerte dit lequel) : **Ajuster** (toute l'image,
  bandes noires), **Remplir** (étirée à tout l'écran), **Zoom** (l'écran rempli, les bords
  coupés). Chaque moteur donne la forme de l'image (`PlayerEngineValue.aspectRatio` : taille de
  la vue native, de la vidéo de mpv, de `video_player`) ; `_FramedVideo` pose la vue à cette forme
  puis l'agrandit (`FittedBox` `contain` / `fill` / `cover`) : le même arbre quel que soit le
  cadrage, la vue native n'est jamais reconstruite. Tant que la forme n'est pas connue, la vue
  prend tout l'écran.

Chaque plugin vidéo n'est importé que par son moteur, et les moteurs seulement par
`engine_factory_io.dart` : `PlayerScreen` ne parle qu'à un `PlayerEngine`.

## Fichiers (`lib/features/playback/engine/`)

```
player_engine.dart           l'abstraction : PlayerEngine, PlayerEngineValue, PlayerSource,
                             PlayerError, DrmConfig
player_errors.dart           Dart pur : tri des erreurs, phrase affichée
engine_factory.dart          playerEngineFactoryProvider
engine_factory_io.dart       Android / iOS -> natif ; Windows -> media_kit ; sinon video_player
native_player_engine.dart    better_native_video_player
media_kit_player_engine.dart media_kit (libmpv), Windows
video_player_engine.dart     video_player
../webvtt.dart               sous-titres WebVTT (lecture du fichier, texte à l'instant t)
```

Parallèle Vue : `PlayerEngine` est un petit store (`ValueNotifier`, comme un `ref()`) que l'écran
observe, avec quelques commandes (`open`, `play`, `pause`, `seekTo`, `setVolume`).
`engine_factory_io.dart` choisit le moteur selon `Platform`, comme une fabrique de services
Laravel qui lirait l'environnement.

## Windows : media_kit

- `MediaKit.ensureInitialized()` est appelé au démarrage (`main.dart`, `_setUpWindows`), avec la
  fenêtre (`window_manager` : titre « Vixeo », 1280×800, 960×600 au minimum, fond de la charte).
- `MediaKitPlayerEngine.open` ouvre le flux en pause (`Media(url, httpHeaders: headers)`) et
  attend sa durée ou sa taille d'image (30 s au plus, sinon `PlayerError(network)`). mpv lit le
  HLS, le MP4, le MPEG-TS et la plupart des codecs (H.264, H.265, AV1…) sans rien installer.
- Volume : 0 à 1 dans l'appli, 0 à 100 pour mpv.
- Vue : `Video(controller:, controls: NoVideoControls)` : les commandes restent celles de Vixeo.
- Plein écran : `windowManager.setFullScreen` (`features/tv/fullscreen/fullscreen_io.dart`) ;
  pas d'orientation à verrouiller.
- Les DLL de libmpv sont copiées à côté de `vixeo.exe` par `media_kit_libs_windows_video` au
  build, puis dans l'installateur (`docs/windows-release.md`).

### Erreurs

Chaque moteur traduit ses erreurs en `PlayerError(kind)` ; l'écran affiche une phrase par cause
(`playerErrorMessage`) et garde ses boutons (« Réessayer », « Changer de source »).

| Cause | D'où | Phrase |
|---|---|---|
| `network` | erreur réseau, HTTP, délai de 30 s | Problème de connexion : la vidéo ne se charge pas. |
| `unsupported`, `decode` | format ou codec inconnu, décodage impossible | Ce format vidéo n’est pas pris en charge par cet appareil. |
| `drm` | flux protégé | Ce contenu protégé ne peut pas être lu ici. |
| `unknown` | le reste | la phrase habituelle (« Impossible de lire cette chaîne. » / « … cette source. ») |

Les moteurs ne donnent souvent qu'un texte (ExoPlayer, AVPlayer, mpv) : `classifyPlayerError` le
trie par mots-clés. L'image figée d'un direct reste surveillée par l'écran (`stallTimeout`, 15 s).

### Sous-titres WebVTT

L'API sert du WebVTT (`/catalog/subtitles/{id}`). `webvtt.dart` le lit et `PlayerScreen` dessine
le texte lui-même par-dessus l'image, à la position donnée par le moteur : même rendu partout,
sans vue native de sous-titres.

### Orientation et plein écran

Le lecteur est **toujours horizontal** (demande du développeur) : `PlayerScreen` appelle
`lockLandscape()` à l'ouverture et `unlockOrientation()` à la fermeture
(`features/tv/fullscreen/`). Android / iOS : paysage seulement tant que le lecteur est ouvert,
plein écran ou non ; le reste de l'appli tourne avec l'appareil. Windows : rien à verrouiller.

Plein écran : mode immersif sur Android / iOS, fenêtre plein écran sur Windows (touche F, Échap
pour sortir).

## DRM : rien n'est implémenté

Un flux marqué protégé (`PlayerSource.drm`) est refusé avec la phrase « Ce contenu protégé ne
peut pas être lu ici. ». Aucune source ne renvoie aujourd'hui de flux protégé. Le contrat
`DrmConfig` (schéma, URL du serveur de licences, URL du certificat FairPlay, en-têtes) existe ;
sur Android / iOS, `NativePlayerEngine` le transmet au plugin (`drmConfig` de
`better_native_video_player`), **jamais essayé** faute de flux protégé. mpv (Windows) ne lit pas
de flux Widevine / PlayReady.

Règle : **aucune clé de licence dans Flutter**. L'appli ne connaît que l'URL du serveur de
licences et un jeton ; les clés restent dans le module DRM du système.

## Tests

Automatiques (`flutter test`, exécutés par la CI) :
- `test/player_engine_test.dart` : tri des erreurs, WebVTT, et `PlayerScreen` avec un faux moteur
  (commandes, flux et en-têtes d'une source, erreurs réseau / format, panne en cours de lecture,
  recherche dans la vidéo, sous-titres, cadrage) ;
- `test/live_player_test.dart` : le lecteur en direct avec `video_player` simulé.

Ces tests tournent sur la machine de test, sans vrai moteur vidéo.

### Matrice manuelle (à cocher)

Flux d'essai : une source d'un plug-in (film, épisode), une chaîne en direct, ou le flux HLS
public de démonstration `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`.

| Essai | Android (téléphone) | Android TV | Windows |
|---|---|---|---|
| MP4 H.264 | ☐ | ☐ | ☐ |
| HLS | ☐ | ☐ | ☐ |
| Flux qui exige un `Referer` | ☐ | ☐ | ☐ |
| Lecture / pause (bouton, appui sur l'image, touche K) | ☐ | ☐ | ☐ |
| Recherche dans la vidéo (barre, ±10 s) | ☐ | ☐ | ☐ |
| Volume, muet (curseur, touche M) | – | – | ☐ |
| Sous-titres | ☐ | ☐ | ☐ |
| Plein écran (bouton, touche F, Échap) | ☐ | – | ☐ |
| Cadrage (Ajuster, Remplir, Zoom) | ☐ | ☐ | ☐ |
| Erreur : URL inexistante | ☐ | ☐ | ☐ |
| Commandes : masquage après 4 s, retour au toucher / à la souris, « Revenir au direct » | ☐ | ☐ | ☐ |

Le moteur utilisé s'affiche dans la console en cas d'échec (`Player engine "media_kit" failed: …`).

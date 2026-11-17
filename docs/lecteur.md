# Lecteur vidéo : architecture multiplateforme

Un seul écran (`PlayerScreen`, `lib/features/playback/player_screen.dart`) et une seule interface
de commandes Flutter, sur toutes les plateformes. Seul le **moteur de lecture** change.

| Plateforme | Moteur | Paquet | Ce qui lit réellement |
|---|---|---|---|
| Android (téléphone, tablette, Android TV) | `NativePlayerEngine` | `better_native_video_player` | ExoPlayer (Media3) |
| iOS | `NativePlayerEngine` | `better_native_video_player` | AVPlayer |
| Web, flux lu par le navigateur (MP4 ; HLS sur Safari) | `VideoPlayerEngine` | `video_player` + `video_player_web` | `<video>` HTML5 |
| Web, HLS ailleurs (Chrome, Firefox, Edge) | `HlsJsEngine` | hls.js 1.5.17 (`web/hls.min.js`) | `<video>` + Media Source Extensions |
| Ordinateur, tests | `VideoPlayerEngine` | `video_player` | selon la plateforme |

`better_native_video_player` n'a **pas** d'implémentation web. Il n'est importé que par
`native_player_engine.dart`, lui-même importé seulement par `engine_factory_io.dart` : la
compilation web ne voit jamais ce paquet, et aucune API native n'est appelée dans un navigateur
(test : `test/web_hls_test.dart`).

## Fichiers (`lib/features/playback/engine/`)

```
player_engine.dart          l'abstraction : PlayerEngine, PlayerEngineValue, PlayerSource,
                            PlayerError, DrmConfig
player_errors.dart          Dart pur : tri des erreurs, phrase affichée, choix du moteur web,
                            en-têtes autorisés par un navigateur
engine_factory.dart         playerEngineFactoryProvider + import conditionnel
engine_factory_io.dart      Android / iOS -> natif ; sinon video_player
engine_factory_web.dart     WebPlayerEngine : choisit HTML5 ou hls.js, repli de l'un vers l'autre
native_player_engine.dart   better_native_video_player
video_player_engine.dart    video_player (HTML5 sur le web)
web/browser_support*.dart   questions au navigateur (HLS natif, MSE, geste, CORS)
web/hls_js_interop.dart     liaisons hls.js + chargement du script à la demande
web/hls_js_engine.dart      <video> + hls.js
../webvtt.dart              sous-titres WebVTT (lecture du fichier, texte à l'instant t)
```

Parallèle Vue : `PlayerEngine` est un petit store (`ValueNotifier`, comme un `ref()`) que l'écran
observe, avec quelques commandes (`open`, `play`, `pause`, `seekTo`, `setVolume`). L'import
conditionnel (`import 'a.dart' if (dart.library.js_interop) 'b.dart'`) est l'équivalent d'un alias
de build : le compilateur ne garde qu'un des deux fichiers.

## Web : choix du moteur

À l'ouverture d'un flux (`WebPlayerEngine.open`) :

1. Le flux est-il du HLS ? Format donné par l'API (`hls`, `m3u8`), sinon l'URL (`.m3u8`).
2. Le navigateur lit-il le HLS seul ? `video.canPlayType('application/vnd.apple.mpegurl')`.
3. hls.js peut-il fonctionner ? `MediaSource` ou `ManagedMediaSource` (iPhone, iOS 17.1+).

| Flux | HLS natif | MSE | Moteur |
|---|---|---|---|
| MP4 | – | – | HTML5 |
| HLS | oui | – | HTML5 (hls.js **n'est pas téléchargé**) |
| HLS | non | oui | hls.js |
| HLS avec en-têtes qu'une page peut envoyer | oui | oui | hls.js (`<video>` n'envoie aucun en-tête) |
| HLS | non | non | HTML5, qui échoue : « format non pris en charge » |

Repli : si le lecteur HTML5 annonce le HLS (« maybe ») puis échoue à l'ouverture (format,
décodage, cause inconnue) et que MSE existe, le flux est rouvert avec hls.js.

`web/index.html` ne charge plus `hls.min.js` : `ensureHlsJsLoaded()` ajoute la balise `<script>`
au premier flux qui en a besoin (toujours depuis notre origine).

### Erreurs

Chaque moteur traduit ses erreurs en `PlayerError(kind)` ; l'écran affiche une phrase par cause
(`playerErrorMessage`) et garde ses boutons (« Réessayer », « Changer de source »).

| Cause | D'où | Phrase |
|---|---|---|
| `network` | `MEDIA_ERR_NETWORK`, hls.js `networkError`, délai de 30 s | Problème de connexion : la vidéo ne se charge pas. |
| `cors` | hls.js `networkError` sans réponse lisible **et** la même URL répond en `no-cors` | Ce flux n’autorise pas la lecture dans un navigateur. |
| `unsupported`, `decode` | `MEDIA_ERR_SRC_NOT_SUPPORTED`, `MEDIA_ERR_DECODE`, codecs incompatibles | Ce format vidéo n’est pas pris en charge par ce navigateur. |
| `drm` | flux protégé | Ce contenu protégé ne peut pas être lu ici. |
| `unknown` | le reste | la phrase habituelle (« Impossible de lire cette chaîne. » / « … cette source. ») |

Limites connues :
- un navigateur ne dit jamais « CORS » à une page : le diagnostic est une déduction (seconde
  requête `no-cors`), faite seulement pour hls.js. `<video>` seul n'a pas besoin de CORS ;
- `video_player` ne transmet que le message de l'erreur après l'ouverture (pas son code) : le tri
  se fait alors sur le texte, différent selon les navigateurs ;
- l'image figée d'un direct reste surveillée par l'écran (`stallTimeout`, 15 s). Sur Android /
  iOS, la position du plugin ne convient pas (bornée à la fenêtre du direct, absente sans
  fenêtre) : le moteur natif donne le temps réellement passé en lecture (arrêté pendant la mise
  en mémoire tampon) ;
- pour un direct, le diagnostic `cors` n'est pas affiché : le flux vient de notre API, et une
  réponse illisible y est une page d'erreur du serveur frontal (chaîne en panne, délai dépassé) ;
- un flux MPEG-TS brut (`format: ts`) n'est lu par aucun navigateur (ni par hls.js).

### Lecture automatique (autoplay)

Un navigateur refuse de démarrer avec le son une vidéo que le spectateur n'a pas demandée.
- HTML5 : si personne n'a encore touché la page (`navigator.userActivation.hasBeenActive`), le
  démarrage se fait **muet**. Si le navigateur refuse quand même, le flux est rouvert en pause.
- hls.js : `play()` refusé → nouvel essai muet → sinon pause.

Démarrage muet : le bouton du son affiche « Activer le son » ; un appui (un vrai geste) remet le
son. En pause : le signe lecture est affiché, un appui sur l'image démarre.

### Sous-titres WebVTT

L'API sert du WebVTT (`/catalog/subtitles/{id}`). `webvtt.dart` le lit et `PlayerScreen` dessine
le texte lui-même par-dessus l'image, à la position donnée par le moteur : même rendu partout,
sans `<track>` ni vue native de sous-titres.

### Plein écran

`features/tv/fullscreen/` (inchangé) : API Fullscreen du navigateur sur l'élément racine, mode
immersif sur Android / iOS. Sur iPhone, Safari n'offre le plein écran qu'à la balise `<video>`
avec ses propres commandes : le bouton reste donc sans effet dans Safari iPhone (iPad : oui).

## DRM Web : étude (rien n'est implémenté)

**État : aucun DRM ne fonctionne sur le web.** Un flux marqué protégé (`PlayerSource.drm`) est
refusé avec la phrase « Ce contenu protégé ne peut pas être lu ici. ». L'API ne renvoie
aujourd'hui aucun flux protégé (`ResolvedStream` et `TvStream` n'ont pas de champ DRM).

Ce qui existe : le contrat `DrmConfig` (schéma, URL du serveur de licences, URL du certificat
FairPlay, en-têtes). Sur Android / iOS, `NativePlayerEngine` le transmet au plugin
(`drmConfig` de `better_native_video_player`), **jamais essayé** faute de flux protégé.

Faisabilité d'un adaptateur EME (Encrypted Media Extensions) :

| Navigateur | Système | Voie | Remarques |
|---|---|---|---|
| Chrome, Edge, Firefox (ordinateur, Android) | Widevine (`com.widevine.alpha`) | hls.js : `emeEnabled`, `drmSystems`, `licenseXhrSetup` | HTTPS obligatoire ; en logiciel (L3) la plupart des serveurs limitent la définition ; Edge sait aussi PlayReady |
| Safari macOS / iPadOS | FairPlay (`com.apple.fps`) | hls.js (MSE + EME) ou `<video>` natif avec les événements `encrypted` | certificat d'application à télécharger ; format des messages propre à chaque serveur de licences |
| Safari iPhone | FairPlay | `<video>` natif, ou hls.js avec `ManagedMediaSource` (iOS 17.1+) | à vérifier sur appareil |

Possible donc, à ces conditions :
1. **Côté API** : renvoyer avec le flux `drm: {scheme, license_url, certificate_url, headers}`,
   les en-têtes portant un jeton à durée courte. Le serveur de licences doit accepter les
   requêtes de l'origine web (CORS) ;
2. **Côté appli** : un `EmeAdapter` dans `HlsJsEngine` (configuration hls.js ci-dessus, en-têtes
   ajoutés dans `licenseXhrSetup`), la détection par
   `navigator.requestMediaKeySystemAccess`, et les erreurs `keySystemError` (déjà triées en `drm`) ;
3. **Tests** : sur de vrais flux et un vrai serveur de licences, navigateur par navigateur.
   FairPlay ne se teste que sur du matériel Apple.

Règle : **aucune clé de licence dans Flutter**. L'appli ne connaît que l'URL du serveur de
licences et un jeton ; les clés restent dans le module DRM (CDM) du navigateur ou du système.

## Tests

Automatiques (`flutter test`, exécutés par la CI) :
- `test/player_engine_test.dart` : choix du moteur web, tri des erreurs, en-têtes, WebVTT, et
  `PlayerScreen` avec un faux moteur (commandes, démarrage muet, erreurs réseau / CORS / format,
  panne en cours de lecture, recherche dans la vidéo, sous-titres) ;
- `test/live_player_test.dart` : le lecteur en direct avec `video_player` simulé (inchangé) ;
- `test/web_hls_test.dart` : hls.js fourni mais pas chargé par `index.html`, le web n'importe
  jamais le plugin natif.

Ces tests tournent sur la machine de test, **pas dans un navigateur**.

### Essais réels dans Chrome (17/11/2026)

Le build web de cette branche a été piloté dans Chrome 153 (Chrome for Testing, sans écran), avec
une fausse API locale et des flux fabriqués par ffmpeg (MP4 H.264 / AAC, HLS H.264, HLS H.265),
servis avec ou sans en-têtes CORS. Constaté :

- MP4 : lecture, pause / reprise (K), muet (M, « Activer le son »), recherche à 50 % par la barre,
  curseur de volume, sous-titres WebVTT au bon moment, plein écran (F) aller-retour, commandes
  masquées après 4 s et rappelées par la souris ; `hls.min.js` jamais demandé ;
- HLS : ce Chrome annonce le HLS natif (`canPlayType` = « maybe ») → moteur HTML5, `hls.min.js`
  jamais demandé ; lecture, pause, recherche à 75 %, muet ;
- HLS avec un en-tête à envoyer, et HLS avec `canPlayType` forcé à vide (ce que répondent Firefox
  et les Chrome plus anciens) → hls.js chargé à la demande ; lecture, pause, recherche, muet ;
- erreurs : playlist 404 et serveur éteint → « Problème de connexion » ; HLS H.265 → repli HTML5
  puis hls.js, puis « format non pris en charge » ; HLS sans CORS par hls.js → « n’autorise pas
  la lecture dans un navigateur » ; le même flux sans CORS par `<video>` natif se lit (normal).

Limites de ces essais : un MP4 en 404 donne « format non pris en charge » (le navigateur ne dit
pas autre chose à la page) ; l'autoplay sans geste et un direct réel n'ont pas été essayés ;
**Safari, Firefox et Edge n'ont pas été essayés du tout**, ni aucun appareil Android / iOS.
La matrice ci-dessous reste donc à faire à la main avant de publier.

### Matrice manuelle (à cocher)

Flux d'essai : un MP4 H.264 et un flux HLS servis par l'API (une chaîne en direct, un film),
ou le flux HLS public de démonstration `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`.

| Essai | Safari | Chrome (153, sans écran) | Firefox | Edge |
|---|---|---|---|---|
| MP4 H.264 | ☐ | ☑ | ☐ | ☐ |
| HLS (moteur attendu) | ☐ HTML5, `hls.min.js` absent de l'onglet Réseau | ☑ HTML5 natif, et hls.js (forcé) | ☐ hls.js | ☐ hls.js |
| Lecture / pause (bouton, appui sur l'image, touche K) | ☐ | ☑ (K) | ☐ | ☐ |
| Recherche dans la vidéo (barre) | ☐ | ☑ | ☐ | ☐ |
| Volume, muet (curseur, touche M) | ☐ | ☑ | ☐ | ☐ |
| Sous-titres | ☐ | ☑ | ☐ | ☐ |
| Plein écran (bouton, touche F, Échap) | ☐ | ☑ (F) | ☐ | ☐ |
| Erreur : URL inexistante | ☐ | ☑ | ☐ | ☐ |
| Erreur : flux H.265 | ☐ | ☑ | ☐ | ☐ |
| CORS : HLS sans `Access-Control-Allow-Origin` | – | ☑ (hls.js) | ☐ | ☐ |
| Autoplay : page rechargée directement sur le lecteur | ☐ | ☐ | ☐ | ☐ |
| Commandes : masquage après 4 s, retour au survol, « Revenir au direct » | ☐ | ☑ (sauf direct) | ☐ | ☐ |

Le moteur utilisé s'affiche dans la console en cas d'échec (`Player engine "hls.js" failed: …`).
À faire aussi sur un téléphone Android, une Android TV et un iPhone (moteur natif).

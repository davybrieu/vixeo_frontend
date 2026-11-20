# Plug-ins : dépôts de scrapers JavaScript (façon Nuvio)

> Décision du développeur, **19/11/2026** : les plug-ins de sources ne sont plus des add-ons Stremio
> appelés par l'API ; ce sont des **scrapers JavaScript** installés depuis des **dépôts**
> (`manifest.json`), comme dans Nuvio. Ils s'exécutent **sur l'appareil** (Android, iOS, web) ou
> **sur le serveur**, selon ce que déclare le dépôt. Cela renverse « l'appli ne parle jamais aux
> plug-ins » (`CONTEXT.md` §3.5 et §5.1) : ces passages sont mis à jour.
> Le catalogue reste celui de TMDb ; un scraper ne fournit que des **sources** (films et séries).
>
> **Compatibilité Nuvio** (20/11/2026, demande du développeur : « faire fonctionner
> [gowaru/gowaru-nuvio-providers](https://github.com/gowaru/gowaru-nuvio-providers) en se basant sur
> ce que fait Nuvio ») : Vixeo lit les dépôts et exécute les scrapers **comme l'appli Nuvio**
> (`tapframe/NuvioMobile`, `PluginRepository.kt`, `PluginRuntime.kt`, `JsBindings.kt`) : même
> lecture de l'adresse et du manifeste, mêmes variables globales, même `fetch` (statut 0 au lieu
> d'une exception), mêmes durées. Les 37 scrapers de ce dépôt se chargent et s'exécutent dans le
> bac à sable (`tools/scraper-runner`, vrai QuickJS), y compris les 4 que QuickJS ne savait pas
> compiler (§3, « QuickJS et `for … of yield` »).

## 1. Vue d'ensemble

```
  Dépôt (manifest.json + scrapers .js)         hébergé par un tiers, ajouté par la personne
            │ téléchargé (directement, ou via POST /scrapers/fetch sur le web)
            ▼
  Appli ── scraper en mode « Appareil » ──►  bac à sable JS (QuickJS / iframe)  ── fetch ──► sites tiers
        └─ scraper en mode « Serveur »   ──►  POST /scrapers/run (l'API fait la même chose)
            │
            ▼
  flux [{ url, name, quality, headers… }]  →  panneau des sources du lecteur
```

- **Un scraper** = un fichier JavaScript (CommonJS, groupé par esbuild) qui exporte `getStreams`.
- **Un dépôt** = un `manifest.json` qui liste ses scrapers.
- **Vixeo ne fournit aucun dépôt ni aucun scraper** et n'en propose aucun par défaut : la personne
  ajoute elle-même l'adresse d'un dépôt, sous sa responsabilité (la page le dit).

## 2. Format du dépôt (`manifest.json`)

Celui des dépôts de Nuvio. Seuls `id` et `filename` sont obligatoires par scraper (`name` vaut
l'`id` s'il manque).

```json
{
  "name": "Mon dépôt",
  "version": "1.0.0",
  "description": "Facultatif",
  "execution": "device",
  "scrapers": [
    {
      "id": "monscraper",
      "name": "Mon scraper",
      "description": "Facultatif",
      "version": "1.2.0",
      "filename": "providers/monscraper.js",
      "supportedTypes": ["movie", "tv"],
      "logo": "https://…/logo.png"
    }
  ]
}
```

- La liste peut s'appeler `scrapers` ou `providers` (les deux sont lus).
- `filename` est relatif au dossier du manifeste, même s'il commence par `/` (comme Nuvio), ou une
  adresse complète (`http://` devient `https://`).
- `supportedTypes` : `movie` et/ou `tv` (par défaut les deux) ; `series`, `show` et `other` valent
  `tv`, comme dans Nuvio.
- `enabled: false` : le scraper est **laissé de côté** (son auteur l'a coupé, un site en panne…),
  comme dans Nuvio. La personne, elle, active ou désactive le dépôt entier (§7).
- `supportedPlatforms` / `disabledPlatforms` : appliqués comme NuvioMobile, avec la plateforme
  `android`, `ios` ou `web` (`currentScraperPlatform`) ; `tv` ne concerne que NuvioTV et n'écarte
  rien dans Vixeo (Android TV a le même moteur que le téléphone).
- Les autres champs (`author`, `logo`, `contentLanguage`, `formats`, `limited`, `hasSettings`,
  `supportsExternalPlayer`…) sont ignorés.
- `execution` (propre à Vixeo) : `device` (défaut) ou `server`, pour tout le dépôt (§4).
- `id` : lettres, chiffres, `-`, `_`, `.` (1 à 64 caractères) ; unique dans le dépôt.

**Adresse du dépôt** (`ScraperRepo.normalizeUrl`, comme Nuvio) : l'adresse d'un dossier reçoit
`/manifest.json` (avec ou sans `/` final, avant `?…`), `https://` est ajouté s'il manque, `http://`
devient `https://` ; une page GitHub du dépôt (`https://github.com/owner/repo`, `…/tree/branche/dossier`,
`…/blob/branche/fichier.json`) devient l'adresse du fichier brut sur `raw.githubusercontent.com`
(`HEAD` = branche par défaut). Exemple : l'adresse donnée par gowaru-nuvio-providers,
`https://raw.githubusercontent.com/Gowaru/gowaru-nuvio-providers/refs/heads/main/`, s'installe telle
quelle.

## 3. Format d'un scraper

```js
async function getStreams(tmdbId, mediaType, season, episode) {
  // tmdbId : texte ("550") ; mediaType : "movie" | "tv"
  // season, episode : nombres pour une série, undefined pour un film (comme Nuvio)
  const r = await fetch(`https://api.example.com/find?id=${tmdbId}`);
  if (!r.ok) return [];               // réseau coupé, adresse refusée… : status 0, jamais d'exception
  const data = await r.json();        // null si le corps n'est pas du JSON
  return [{ url: data.link, name: 'Serveur 1', quality: '1080p', headers: { Referer: 'https://example.com/' } }];
}
module.exports = { getStreams };
```

`getStreams` est cherché dans `module.exports` puis dans `globalThis` (les dépôts Nuvio, groupés
par esbuild en IIFE, font les deux).

Chaque flux renvoyé : `url` (**obligatoire**, `https://` ou `http://` ; un objet `{ url }` est
accepté comme dans Nuvio), et facultativement `name`, `title` (la ligne affichée, comme dans Nuvio :
titre, sinon nom, sinon nom du scraper ; la qualité est ajoutée si le titre ne la dit pas, puis la
taille), `quality`, `size`, `language` (« fr », « multi »…), `type` (`hls` / `m3u8`, `mp4`, `mkv`… :
aide le lecteur à choisir son moteur), `headers` (texte → texte, envoyés au lecteur). Un texte qui
contient « [object » est ignoré (règle de Nuvio). Un élément sans `url` valide est ignoré ; 100 flux
au plus. `subtitles`, `seeders`, `infoHash`… sont ignorés. Une exception ou une promesse qui ne se
termine pas est une erreur du scraper (le panneau affiche « Réessayer »), jamais un plantage.

### Ce que le bac à sable fournit (`assets/scrapers/sandbox.js`)

Comme l'appli Nuvio : `console`, `fetch` (+ `Headers`, `Response`, `AbortController`), `URL`,
`URLSearchParams`, `TextEncoder`, `TextDecoder`, `atob`, `btoa`, `setTimeout` / `clearTimeout`,
`setInterval` / `clearInterval`, `queueMicrotask`, `module`, `exports`, `global`, `self`, `window`
(= `globalThis`), `SCRAPER_ID` (`{adresse du manifeste en minuscules}:{id}`), `SCRAPER_SETTINGS`
(toujours `{}` : Vixeo n'a pas de page de réglages par scraper, chaque scraper garde ses réglages par
défaut) et **`CryptoJS`** (crypto-js 4.2.0, MIT, `assets/scrapers/crypto-js.min.js`), prêté
seulement aux scrapers dont le code le nomme (`CryptoJS` ou `'crypto-js'`), aussi par
`require('crypto-js')`.

**Le `fetch` de Nuvio, pas celui du navigateur** :

- une requête impossible (réseau, adresse refusée par la garde, trop de requêtes, délai) donne une
  réponse `status: 0`, `ok: false`, corps vide, `statusText` = la raison ; jamais d'exception ;
- `response.json()` donne `null` quand le corps n'est pas du JSON (ou est vide) ;
- un corps coupé à la limite (§5) se termine par `\n...[truncated]`, que les scrapers Nuvio
  cherchent avant d'analyser une page ;
- `http://` est fait en `https://` (Nuvio accepte http ; Vixeo n'envoie jamais une requête de
  scraper en clair) ;
- sans `User-Agent`, un navigateur Chrome est annoncé ; sans `Content-Type`, un corps part en
  `application/x-www-form-urlencoded` (le défaut d'OkHttp, donc de Nuvio) ; `Accept-Encoding` est
  retiré (la pile HTTP choisit la compression et la défait) ;
- `AbortController` interrompt vraiment l'attente d'une requête (mieux que Nuvio, sans effet pour
  un scraper écrit pour lui).

**Absents** : `cheerio` en variable globale ou par `require` (`require` d'autre chose que
`crypto-js` lève « Module '…' is not available », comme Nuvio quand il ne l'a pas) : les dépôts
Nuvio groupent leur propre cheerio dans chaque fichier ; `TMDB_API_KEY` (la clé TMDb de Vixeo ne sort
pas du serveur ; les scrapers ont leur propre clé de secours) ; `crypto.subtle` dans QuickJS
(Android ; les scrapers le testent et passent à CryptoJS) ; `Buffer`, `process`, DOM,
`XMLHttpRequest`, `WebSocket`, stockage ; le pont `sendMessage` de `flutter_js` (supprimé par le
prélude). `Response.arrayBuffer()` encode le texte reçu en UTF-8 : les réponses binaires ne sont pas
prises en charge.

### QuickJS et `for … of yield`

QuickJS (toutes les versions essayées, de 2021 à 2025, donc celle de `flutter_js` sur Android) ne
sait pas compiler un générateur qui a `yield` dans la tête d'une boucle `for … of` (« stack
underflow », « nip_catch: no catch op »). esbuild écrit exactement cela quand un scraper qui fait
`for (const x of await f())` est compilé pour une cible ancienne (gowaru-nuvio-providers vise
`es2016` : `fullanime`, `jetanimes`, `mugiwarastream`, `voiranime` ne se chargeaient pas). Quand la
compilation échoue ainsi (`InternalError`), le prélude sort l'opérande de la boucle
(`var __vxOf0 = yield f(); for (… of __vxOf0)`, `hoistForOfYield`) et compile à nouveau ; JavaScriptCore
(iOS) et les navigateurs n'en ont pas besoin.

## 4. Où s'exécute un scraper

Déclaré **par le dépôt** (`execution` du manifeste), pour tous ses scrapers ; l'appli l'affiche
sans le proposer comme réglage :

| Mode | Android / iOS | Web |
|------|---------------|-----|
| **Appareil** (défaut) | QuickJS (`flutter_js`) ; les requêtes partent de l'appareil | iframe `sandbox="allow-scripts"` sans origine, CSP `connect-src 'none'` ; les requêtes passent par `POST /scrapers/fetch` (CORS) |
| **Serveur** | `POST /scrapers/run` | `POST /scrapers/run` |

Même prélude (`sandbox.js`), même boucle (`ScraperRunner` en Dart, `tools/scraper-runner/host.mjs`
en JS), mêmes limites partout. Sur Android, le moteur est `QuickJsRuntime2` créé directement (pas le
`fetch` du paquet ; **pas de plafond de mémoire** : la bibliothèque QuickJS de `flutter_js`,
fastdev-jsruntimes-quickjs 0.3.6, n'a pas `jsSetMemoryLimit`, et le demander empêchait le moteur de
démarrer, donc tous les scrapers échouaient) ; sur iOS, `JavascriptCoreRuntime`. Six scrapers tournent en
même temps au plus (`ScraperService.maxParallel` ; Nuvio en lance dix) : un dépôt comme
gowaru-nuvio-providers en a une trentaine, qui attendent surtout le réseau. Le mode « Serveur » convient aux appareils faibles ou aux sites qui
refusent les adresses d'abonnés ; le mode « Appareil » n'expose pas l'adresse du serveur.

## 5. Garde-fous (mêmes règles sur l'appareil, sur le serveur et dans `tools/`)

Un scraper est du code d'un tiers : il n'a **aucun accès direct** au réseau. Chaque `fetch` passe
par l'hôte, qui refuse :

- tout autre protocole que **`https:`** (une adresse `http://` est d'abord changée en `https://`) ;
  les identifiants dans l'adresse ;
- `localhost`, les noms en `.local` / `.internal` / `.lan`…, les noms sans point ;
- les adresses IP privées ou réservées (10/8, 127/8, 169.254/16, 172.16/12, 192.168/16, 100.64/10,
  0/8, ≥ 224, IPv6 `::1`, `fc00::/7`, `fe80::/10`, IPv4 « mappées ») ;
- les redirections vers une adresse refusée (chaque saut est revérifié).

Les durées sont celles de l'appli Nuvio, pour laquelle les scrapers sont écrits (les scrapers de
gowaru-nuvio-providers visent 45 s au plus et en prennent jusqu'à 45 s quand un site répond mal ;
l'ancienne limite de 30 s et 40 requêtes en coupait plusieurs) :

| Limite | Valeur |
|--------|--------|
| Durée d'un scraper | 60 s (Nuvio : 60 s) |
| Durée d'une requête | 30 s (NuvioTV : 30 s) |
| Requêtes par exécution | 200 (filet de sécurité ; Nuvio n'en a pas) |
| Taille d'une réponse | 5 Mo (le reste est coupé, suivi de `\n...[truncated]` ; Nuvio : 1 Mo) |
| Corps d'une requête | 256 Ko |
| `setTimeout` / `setInterval` | 60 s au plus |
| Mémoire / pile du bac à sable | pas de plafond sur l'appareil (§4), 256 Mo dans `tools/scraper-runner` / pile 1 Mo |
| Flux gardés | 100 par scraper |

Le jeton Vixeo n'est **jamais** envoyé à un scraper ni à un site tiers (client HTTP séparé de
`ApiClient`). Sur l'appareil, le nom d'hôte est aussi résolu avant la requête et refusé s'il
mène à une adresse privée (la résolution peut encore changer entre le contrôle et la requête :
le serveur, lui, doit **fixer l'adresse résolue**, voir §6). Le refus donne l'adresse obtenue
(« adresse privée interdite (api.exemple.fr → 127.0.0.1) ») : `127.0.0.1` ou `0.0.0.0` pour un site
public, c'est en général le DNS du réseau (fournisseur d'accès, filtre) qui bloque ce nom, pas le site.
De `192.0.0.0/16`, seuls `192.0.0.0/24` et `192.0.2.0/24` sont réservés : le reste est public.

## 6. API du serveur (à implémenter dans `vixeo_backend`)

Toutes demandent le jeton Vixeo. Le serveur applique les règles du §5 et le comportement Nuvio du §3
(`http://` fait en `https://`, `\n...[truncated]` après un corps coupé, `User-Agent` et
`Content-Type` par défaut, `Accept-Encoding` retiré) ; il **résout le nom, refuse une adresse privée
et se connecte à l'adresse vérifiée** (pas de re-résolution : sinon un nom qui change de cible,
« DNS rebinding », contourne la garde), revérifie chaque redirection, limite le débit par compte et
ne journalise pas les corps. Le débit doit suivre un vrai dépôt : gowaru-nuvio-providers lance une
trentaine de scrapers par épisode, qui font chacun de 2 à 60 requêtes (plutôt 1 000 requêtes par
minute et par compte que 120).

- `POST /scrapers/fetch` : `{ url, method, headers, body, redirect }` →
  `{ status, status_text, headers, body, url }` (corps en texte UTF-8, 5 Mo au plus). Sert au web
  (CORS) : téléchargement des dépôts et requêtes des scrapers en mode « Appareil ».
- `POST /scrapers/run` : `{ repository_url, scraper_id, tmdb_id, media_type, season, episode }` →
  `{ data: [ { url, name, title, quality, size, headers } ] }`. Le serveur télécharge le manifeste et
  le scraper (cache par empreinte), l'exécute dans le même bac à sable (voir
  `tools/scraper-runner`, qui sert de modèle) et normalise les flux comme `normalizeStreams`. Délai
  du client : 65 s.
- `POST /scrapers/stream` (**web seulement**) : `{ url, headers }` →
  `{ data: { stream, stream_type, headers } }` : une adresse sur **notre origine** (proxy signé,
  comme `/tv/channels/{id}/stream`) pour qu'un navigateur lise un flux qui exige des en-têtes ou
  n'a pas de CORS. Sur Android et iOS, le lecteur natif envoie lui-même les en-têtes.

Rien n'est stocké côté serveur sur les dépôts de la personne : la liste des dépôts et les
réglages restent **sur l'appareil** (§7).

## 7. Stockage sur l'appareil

`LocalStore` (stockage protégé), clé `vixeo.scrapers.<id du compte>` : une liste JSON de dépôts
`{ url, name, description, version, mode, enabled, scrapers: [ { id, name, filename, version, supportedTypes, logo } ] }`
dans l'ordre choisi par la personne.

La page « Plug-ins » ne montre que les **dépôts** (les add-ons), jamais leurs scrapers : chacun
s'**active / se désactive** en entier (`enabled` ; désactivé, il reste installé mais ses scrapers
ne donnent plus de sources) et se **déplace** (monter / descendre) : le panneau des sources du
lecteur suit l'ordre des dépôts. Les scrapers d'un dépôt gardent l'ordre de son manifeste ;
« Mettre à jour » relit le manifeste et ne garde que `enabled` (un scraper que l'auteur a coupé
depuis disparaît, un scraper rallumé revient). Le code des scrapers n'est **pas** stocké : il est
téléchargé à la première utilisation puis gardé en mémoire jusqu'à la fermeture de l'appli.
Pas de synchronisation entre appareils (il faudrait un champ de compte côté API).

## 8. Tester un scraper

```bash
cd tools/scraper-runner && npm install
node cli.mjs monscraper.js 550 movie            # un film
node cli.mjs monscraper.js 1399 tv 1 2          # saison 1, épisode 2
node cli.mjs gowaru-nuvio-providers/providers/coflix.js 550 movie   # un fichier d'un dépôt Nuvio
npm test                                        # le bac à sable lui-même (vrai QuickJS)
```

Le même contrôle réseau que l'appli s'y applique : si le scraper passe ici, il passe dans l'appli.

## 8 bis. Journal d'une source (diagnostic sur l'appareil)

Dans le panneau des sources du lecteur, un **appui long** sur une source ouvre son journal
(`ScraperJournal`) : chaque requête (méthode, adresse, statut ou raison de l'échec, durée, taille),
ce que le scraper écrit dans sa console (`[log]`, `[warn]`, `[error]`), les requêtes refusées par la
garde (`[garde]`) et la fin (« fin : N flux » ou l'erreur). Seul le dernier passage de chaque source
est gardé, en mémoire (400 lignes au plus) ; « Copier » le met dans le presse-papiers. C'est la façon
de savoir, sur un téléphone, pourquoi une source ne trouve rien. Un appui simple relance une source en
« Échec » comme une source à « Aucune source » (un site en panne un instant plus tôt peut répondre). Les corps se lisent dans le
`charset` de leur `Content-Type` (Latin-1 pour `iso-8859-1` / `windows-1252`, UTF-8 sinon), comme
Nuvio.

## 9. Points ouverts

- `flutter_js` (QuickJS / JavaScriptCore) et l'iframe web n'ont pas pu être essayés sur un appareil
  ni dans un navigateur dans les sessions qui ont écrit ce code (pas de SDK Flutter) : la CI compile
  et teste le Dart, `tools/scraper-runner` teste le JavaScript avec un vrai QuickJS (dont les 37
  scrapers de gowaru-nuvio-providers, sans réseau : ils se chargent, s'exécutent et finissent).
- QuickJS libère mal certains contextes : dans le QuickJS de `tools/scraper-runner` (build avec
  assertions), libérer le moteur après quelques scrapers réels déclenche
  `Assertion failed: list_empty(&rt->gc_obj_list)` (le module est alors recréé). Le QuickJS de
  `flutter_js` est compilé en Release (assertions coupées, en principe) : à surveiller sur Android.
- Web : rien ne marche sans les routes `/scrapers/fetch` et `/scrapers/stream` de `vixeo_backend`
  (CORS) ; `crypto.subtle` existe dans l'iframe si la page est en https.
- Pas de page de réglages par scraper (`hasSettings` / `onSettings` de Nuvio, demande du développeur :
  « Plug-ins » ne montre que les dépôts) : `SCRAPER_SETTINGS` vaut toujours `{}`, donc les options
  d'un scraper (solveur Turnstile de Coflix, filtres de Frenchstream…) restent à leur valeur par
  défaut.
- Sous-titres fournis par un scraper (`subtitles`) : ignorés.
- iOS : l'exécution de code téléchargé relève de la règle 2.5.2 de l'App Store ; Vixeo n'est pas
  distribuée par l'App Store pour l'instant, à revoir avant toute publication.

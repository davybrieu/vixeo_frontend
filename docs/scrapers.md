# Plug-ins : dépôts de scrapers JavaScript (façon Nuvio)

> Décision du développeur, **19/11/2026** : les plug-ins de sources ne sont plus des add-ons Stremio
> appelés par l'API ; ce sont des **scrapers JavaScript** installés depuis des **dépôts**
> (`manifest.json`), comme dans Nuvio. Ils s'exécutent **sur l'appareil** (Android, iOS, web) ou
> **sur le serveur**, selon ce que déclare le dépôt. Cela renverse « l'appli ne parle jamais aux
> plug-ins » (`CONTEXT.md` §3.5 et §5.1) : ces passages sont mis à jour.
> Le catalogue reste celui de TMDb ; un scraper ne fournit que des **sources** (films et séries).

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

Compatible avec les dépôts de Nuvio. Seuls `id`, `name` et `filename` sont obligatoires par scraper.

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
- `filename` est relatif à l'adresse du manifeste (ou une adresse `https://` complète).
- `supportedTypes` : `movie` et/ou `tv` (par défaut les deux). Les champs inconnus sont ignorés
  (dont `enabled` d'un scraper : on active ou désactive le dépôt entier, voir §7).
- `execution` : `device` (défaut) ou `server`, pour tout le dépôt (§4).
- `id` : lettres, chiffres, `-`, `_`, `.` (1 à 64 caractères) ; unique dans le dépôt.
- Adresse du dépôt : `https://…/manifest.json` seulement (pas `http://`).

## 3. Format d'un scraper

```js
async function getStreams(tmdbId, mediaType, season, episode) {
  // tmdbId : texte ("550") ; mediaType : "movie" | "tv"
  // season, episode : nombres pour une série, null pour un film
  const r = await fetch(`https://api.example.com/find?id=${tmdbId}`);
  const data = await r.json();
  return [{ url: data.link, name: 'Serveur 1', quality: '1080p', headers: { Referer: 'https://example.com/' } }];
}
module.exports = { getStreams };
```

Chaque flux renvoyé : `url` (**obligatoire**, `https://` ou `http://`), et facultativement `name`
(ou `title`, `provider`), `title`, `quality`, `size`, `headers` (texte → texte, envoyés au lecteur).
Un élément sans `url` valide est ignoré ; 50 flux au plus. Une exception ou une promesse qui ne se
termine pas est une erreur du scraper (le panneau affiche « Réessayer »), jamais un plantage.

### Ce que le bac à sable fournit (`assets/scrapers/sandbox.js`)

`console`, `fetch` (+ `Headers`, `Response`, `AbortController`), `URL`, `URLSearchParams`,
`TextEncoder`, `TextDecoder`, `atob`, `btoa`, `setTimeout` / `clearTimeout`, `queueMicrotask`,
`module`, `exports`, `global`, `self`.

**Absents** : `require` (sauf erreur « module introuvable »), `Buffer`, `process`, DOM,
`XMLHttpRequest`, `WebSocket`, stockage. Les bibliothèques (analyse HTML, crypto…) doivent être
**groupées dans le fichier** du scraper. `Response.arrayBuffer()` encode le texte reçu en UTF-8 :
les réponses binaires ne sont pas prises en charge.

> **À vérifier avec de vrais dépôts Nuvio** : les scrapers qui comptent sur une bibliothèque que
> Nuvio met à leur disposition (par exemple `require('cheerio-without-node-native')`) ne
> fonctionneront pas tant que Vixeo ne la fournit pas aussi. Le contrat exact de Nuvio n'est pas
> documenté de façon officielle : ce document décrit ce que Vixeo accepte.

## 4. Où s'exécute un scraper

Déclaré **par le dépôt** (`execution` du manifeste), pour tous ses scrapers ; l'appli l'affiche
sans le proposer comme réglage :

| Mode | Android / iOS | Web |
|------|---------------|-----|
| **Appareil** (défaut) | QuickJS (`flutter_js`) ; les requêtes partent de l'appareil | iframe `sandbox="allow-scripts"` sans origine, CSP `connect-src 'none'` ; les requêtes passent par `POST /scrapers/fetch` (CORS) |
| **Serveur** | `POST /scrapers/run` | `POST /scrapers/run` |

Même prélude (`sandbox.js`), même boucle (`ScraperRunner` en Dart, `tools/scraper-runner/host.mjs`
en JS), mêmes limites partout. Le mode « Serveur » convient aux appareils faibles ou aux sites qui
refusent les adresses d'abonnés ; le mode « Appareil » n'expose pas l'adresse du serveur.

## 5. Garde-fous (mêmes règles sur l'appareil, sur le serveur et dans `tools/`)

Un scraper est du code d'un tiers : il n'a **aucun accès direct** au réseau. Chaque `fetch` passe
par l'hôte, qui refuse :

- tout autre protocole que **`https:`** ; les identifiants dans l'adresse ;
- `localhost`, les noms en `.local` / `.internal` / `.lan`…, les noms sans point ;
- les adresses IP privées ou réservées (10/8, 127/8, 169.254/16, 172.16/12, 192.168/16, 100.64/10,
  0/8, ≥ 224, IPv6 `::1`, `fc00::/7`, `fe80::/10`, IPv4 « mappées ») ;
- les redirections vers une adresse refusée (chaque saut est revérifié).

| Limite | Valeur |
|--------|--------|
| Durée d'un scraper | 30 s |
| Durée d'une requête | 15 s |
| Requêtes par exécution | 40 |
| Taille d'une réponse | 5 Mo (le reste est coupé) |
| Corps d'une requête | 256 Ko |
| `setTimeout` | 5 s au plus |
| Mémoire / pile du bac à sable | 64 Mo / 1 Mo |
| Flux gardés | 50 |

Le jeton Vixeo n'est **jamais** envoyé à un scraper ni à un site tiers (client HTTP séparé de
`ApiClient`). Sur l'appareil, le nom d'hôte est aussi résolu avant la requête et refusé s'il
mène à une adresse privée (la résolution peut encore changer entre le contrôle et la requête :
le serveur, lui, doit **fixer l'adresse résolue**, voir §6).

## 6. API du serveur (à implémenter dans `vixeo_backend`)

Toutes demandent le jeton Vixeo. Le serveur applique les règles du §5 ; il **résout le nom, refuse
une adresse privée et se connecte à l'adresse vérifiée** (pas de re-résolution : sinon un nom qui
change de cible, « DNS rebinding », contourne la garde), revérifie chaque redirection, limite le
débit par compte (par exemple 120 requêtes par minute) et ne journalise pas les corps.

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
« Mettre à jour » relit le manifeste et ne garde que `enabled`. Le code des scrapers n'est **pas** stocké : il est
téléchargé à la première utilisation puis gardé en mémoire jusqu'à la fermeture de l'appli.
Pas de synchronisation entre appareils (il faudrait un champ de compte côté API).

## 8. Tester un scraper

```bash
cd tools/scraper-runner && npm install
node cli.mjs monscraper.js 550 movie            # un film
node cli.mjs monscraper.js 1399 tv 1 2          # saison 1, épisode 2
npm test                                        # le bac à sable lui-même (vrai QuickJS)
```

Le même contrôle réseau que l'appli s'y applique : si le scraper passe ici, il passe dans l'appli.

## 9. Points ouverts

- `flutter_js` (QuickJS) et l'iframe web n'ont pas pu être compilés ni essayés dans la session qui
  a écrit ce code (pas d'accès à pub.dev ni au SDK Dart) : voir les notes de `CLAUDE.md`.
- iOS : l'exécution de code téléchargé relève de la règle 2.5.2 de l'App Store ; Vixeo n'est pas
  distribuée par l'App Store pour l'instant, à revoir avant toute publication.
- Fournir `cheerio` et `crypto-js` comme Nuvio le fait peut-être (voir §3).

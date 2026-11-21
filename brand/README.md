# Logo Vixeo

Le logo : un **V blanc** et un **triangle vert** le long de sa branche droite, puis « **Vixeo** »
en **Sora ExtraBold** (police de l'appli, `assets/fonts`, licence OFL). Couleurs de la charte
graphique (`docs/charte-graphique.md`) :

| Élément | Couleur | Nom dans le code |
| --- | --- | --- |
| V et « Vixeo » | `#F1F5F2` | `VxColors.text` |
| Triangle | `#2EE58A` | `VxColors.accent` |
| Fond (icônes, version sur fond) | `#070A08` | `VxColors.background` |

## Fichiers

| Fichier | Usage |
| --- | --- |
| `vixeo-logo.svg` / `.png` (1440 × 320) | logo complet, fond transparent, pour un fond sombre |
| `vixeo-logo-fond.svg` / `.png` | le même sur le fond de la charte (documents, réseaux sociaux) |
| `vixeo-mark.svg` / `.png` | le symbole seul (V et triangle) |
| `icons/favicon.svg` (+ `favicon.ico`) | favicon : le symbole sur un carré arrondi |
| `icons/icon.svg` | icônes d'appli carrées (Apple, iOS, site) : le système arrondit les coins |
| `icons/icon-rounded.svg` | icône Android avant la version 8 et icône Windows (carré arrondi) |
| `icons/icon-maskable.svg` | icône « maskable » (symbole dans le cercle de sécurité ; servait à l'appli web, gardée pour mémoire) |

Les SVG n'ont pas besoin de la police : « Vixeo » y est dessiné en contours. Proportions : le
symbole fait 80 de haut et 117 de large, le mot commence 20 après lui, sa hauteur de capitale
fait 0,69 fois celle du symbole, et le tout fait 360 × 80.

## Où il est utilisé

Le même logo et le même favicon partout :

- **appli** : `VxLogo` (`lib/core/widgets/common.dart`) le dessine avec les mêmes formes, net à
  toutes les tailles ;
- **Windows** : `windows/runner/resources/app_icon.ico` (16 à 256, d'après `icons/icon-rounded.svg`),
  icône de `vixeo.exe`, de la fenêtre et de l'installateur ;
- **Android** : icône adaptative (`mipmap-anydpi-v26/ic_launcher.xml` : le symbole
  `drawable/ic_launcher_foreground.xml` sur le fond `#070A08`, aussi pour les icônes à thème
  d'Android 13), icônes PNG d'avant Android 8 (`mipmap-*/ic_launcher.png`), bannière Android TV
  (`drawable/tv_banner.xml` : le logo complet) ;
- **iOS** : `ios/Runner/Assets.xcassets/AppIcon.appiconset` (toutes les tailles, sans transparence) ;
- **site** (`vixeo_backend`, ancien `vixeo_web`) : composant `VxLogo.vue` (le même SVG), `public/favicon.svg` / `.ico`,
  `apple-touch-icon.png`, image de partage `og-image.jpg`, maquettes de l'appli ;
- **API** (`vixeo_backend`) : `public/favicon.ico`.

## Régénérer

Depuis la racine du dépôt :

```bash
pip install fonttools uharfbuzz pillow
python3 brand/tools/make_logo.py              # SVG de brand/ et dessins Android (XML)
node brand/tools/raster.js brand/tools/icons.json   # PNG (Playwright)
python3 brand/tools/finish_icons.py           # favicon.ico, app_icon.ico (Windows), icônes sans transparence
```

Puis copier `brand/vixeo-logo.svg` et les fichiers de `brand/icons/` dans le site et l'API.

## Logos des sites de notes

Le logo d'IMDb affiché à côté de ses notes est dans `ratings/` (marque de son propriétaire ;
origine et régénération : `ratings/README.md`).

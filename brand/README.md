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

Les SVG n'ont pas besoin de la police : « Vixeo » y est dessiné en contours. Proportions : le
symbole fait 80 de haut et 117 de large, le mot commence 20 après lui, sa hauteur de capitale
fait 0,69 fois celle du symbole, et le tout fait 360 × 80.

Dans l'appli, le logo est dessiné par `VxLogo` (`lib/core/widgets/common.dart`) avec les mêmes
formes : il reste net à toutes les tailles. Favicon et icônes de l'appli web : `web/favicon.svg`,
`web/favicon.png` (48), `web/favicon.ico` (16, 32, 48), `web/icons/` (192, 512, versions
« maskable » et `apple-touch-icon.png`).

## Régénérer

```bash
pip install fonttools uharfbuzz
python3 brand/tools/make_logo.py assets/fonts/Sora-ExtraBold.ttf <dossier>   # SVG
node brand/tools/raster.js <jobs.json>                                        # PNG (Playwright)
```

`jobs.json` : une liste `[svg, png, largeur, hauteur, fond (vide = transparent)]`.

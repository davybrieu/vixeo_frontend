# Charte graphique de Vixeo

Ce document décrit l'apparence de l'appli : couleurs, textes, espacements, composants et focus à
la télécommande. Il fait foi pour tout nouvel écran. Le design de référence est le canevas du projet
(planche « Charte ») : https://claude.ai/artifact/ESe8nVYEhsSdPbzeV8UdNc.

Les valeurs sont dans le code, et il faut s'en servir plutôt que d'écrire des nombres :

| Où | Quoi |
| --- | --- |
| `lib/core/theme.dart` | couleurs (`VxColors`), polices et styles de texte (`VxFonts`, `VxText`) |
| `lib/core/design.dart` | espacements (`VxSpace`), rayons (`VxRadius`), tailles (`layout.size`, `layout.space`, tailles de texte) |
| `lib/core/device/layout.dart` | téléphone, tablette ou grand écran ; marges de page (`gutter`) ; conversion TV (`tv`) |
| `lib/core/widgets/` | composants : boutons, puces, champs, cartes, en-tête de page, états vides, focus |

## 1. Principes

- **Noir profond, un seul vert.** Le fond est presque noir. Le vert Vixeo ne sert qu'à l'action
  principale, au focus, à la progression et à l'onglet actif. Il n'est jamais décoratif.
- **La même chose partout.** Un même élément (titre de page, champ de recherche, puce, carte) a la
  même taille et le même espacement sur toutes les pages. On passe donc par les composants communs
  (§ 7) plutôt que de refaire un bloc à la main.
- **Lisible à 3 mètres.** Sur TV, aucun texte n'est sous 18 px (sur un écran de 1920 × 1080), et un
  seul élément a le focus, bien visible.
- **Une base de code.** Une seule page sert le téléphone, la tablette et la TV. Seules les tailles
  changent, selon la règle du § 4.

## 2. Couleurs (`VxColors`)

| Nom | Code | Valeur | Usage |
| --- | --- | --- | --- |
| Fond | `background` | `#070A08` | fond de toutes les pages |
| Surface | `surface` | `#101512` | cartes, panneaux, fenêtres, listes |
| Champ | `field` | `#141A16` | champs de saisie |
| Surface haute | `surfaceHigh` | `#1F2722` | puces, badges, boutons sombres, bordure des cartes |
| Ligne | `line` | `#2A332D` | bordures fines, séparateurs |
| Ligne forte | `lineStrong` | `#3A453E` | contour des puces et des boutons « contour » |
| Vert Vixeo | `accent` | `#2EE58A` | action principale, focus, progression, onglet actif, puce choisie |
| Vert survol | `accentHover` | `#7CF0B4` | liens survolés |
| Texte sur vert | `onAccent` | `#03140A` | texte des boutons verts |
| Texte | `text` | `#F1F5F2` | titres, texte principal |
| Texte doux | `textSoft` | `#C9D1CB` | résumés, informations (année, durée) |
| Texte secondaire | `textSecondary` | `#A9B3AC` | sous-titres, libellés, genres |
| Texte discret | `textMuted` | `#808B84` | aides, mentions, icônes inactives |
| Erreur | `error` | `#FF7A7A` | champs en erreur, messages d'erreur |
| Danger | `danger` / `dangerText` | `#B42318` / `#EF4444` | actions destructives : bouton plein (supprimer), texte rouge (se déconnecter) |

Règles :
- Les tons des affiches sans image viennent de `VxColors.tone(id)` : toujours la même couleur pour
  un même titre.
- Une puce ou un bouton choisi prend le vert à 14 % d'opacité en fond, avec un texte vert.
- Contraste au moins AA (4,5:1 pour le texte courant). Le texte discret n'est jamais utilisé pour
  une information essentielle.

## 3. Textes (`VxText`)

Deux polices, livrées avec l'appli (`assets/fonts`, licence OFL, rien n'est téléchargé) : **Sora**
pour les titres (`VxText.title`, interligne 1,15) et **Inter** pour le texte (`VxText.body`,
interligne 1,45).

| Rôle | Téléphone | TV (1920 × 1080) | Graisse | Dans le code |
| --- | --- | --- | --- | --- |
| Titre de la grande image | 32–36 | 88–100 | 800 | `VxText.title(…, weight: w800)` |
| Titre de page (Recherche, Ma liste, Mes avis) | 28 | 56 | 700 | `layout.pageTitleSize` |
| Titre de rangée ou de section | 18 | 30 | 700 | `layout.sectionTitleSize`, `SectionHeader` |
| Corps (résumé, commentaire) | 15–16 | 22–24 | 400 | `layout.bodySize` |
| Légende (date, durée, « Ma note ») | 13 | 18 | 400–600 | `layout.captionSize` |
| Bouton | 16 | 24 | 600 | `VxButton` |
| Puce | 14 | 24 | 500–600 | `FilterChipButton` |

Sur TV, jamais moins de 18 px.

## 4. Tailles sur chaque écran

- **Téléphone et tablette** : les valeurs sont en pixels logiques.
- **Grand écran et TV** : les valeurs sont celles du design 1920 × 1080, converties à la taille réelle
  de l'écran par `layout.tv(px)`, qui vaut `px × largeur / 1920`.
- Quand un élément a une taille TV à lui, on écrit `layout.size(16, tv: 24)` (16 sur téléphone, 24
  sur TV). C'est ce que font `VxButton`, `VxIconAction`, `FilterChipButton` et les tailles de texte
  ci-dessus.
- Un **espacement** de l'échelle s'écrit `layout.space(VxSpace.m)` : la même marche, multipliée par
  1,5 sur TV (16 → 24, 24 → 36).
- Formats d'écran (`Layout.of(context)`) :
  - téléphone, moins de 600 px ;
  - tablette, de 600 à 1199 px ;
  - grand écran, à partir de 1200 px ou sur une TV détectée.

> Ancienne règle, à faire disparaître : certaines pages (informations du compte, fenêtres)
> multiplient encore les tailles du téléphone par `uiScale(context)` (1,6 × l'échelle) ou par
> `layout.scale * 2`. On les passe à `layout.size` et `layout.space` quand on les retouche.

## 5. Espacements (`VxSpace`)

Une seule échelle : **4 · 8 · 12 · 16 · 24 · 32 · 48 · 64** (`xxs`, `xs`, `s`, `m`, `l`, `xl`,
`xxl`, `xxxl`).

Les écarts d'une page ont un nom (`design.dart`, extension `VxSizes`) : on écrit le nom, jamais le
nombre.

| Usage | Téléphone | TV | Dans le code |
| --- | --- | --- | --- |
| Marge de page | 20 (tablette 32) | 96, soit 5 % de marge de sécurité | `layout.gutter` |
| Entre deux rangées ou deux sections | 24 | 36 | `layout.sectionGap` |
| Sous un titre de rangée ou de section | 12 | 22 | `layout.titleGap` (`SectionHeader`) |
| Sous le texte d'introduction d'une page | 16 | 24 | `layout.introGap` (`InfoIntro`) |
| Entre deux lignes d'une liste (avis, appareils, profils) | 12 | 18 | `layout.listGap` |
| Entre deux cartes d'une rangée ou d'une grille (affiches, épisodes, personnes, avatars) | 10 | 28 | `layout.cardGap` |
| Entre deux puces | 8 | 14 | `FilterBar.gapOf` |
| Entre des puces et ce qu'elles filtrent | 16 | 24 | `layout.space(VxSpace.m)` |
| Entre une image et son texte | 12 | 18 | `layout.space(VxSpace.s)` |
| Bas d'une page qui défile | 32 + barre d'onglets | 48 | `pageBottomPadding(context)` |

- **Bas de page** : `pageBottomPadding` ajoute la place de la barre d'onglets du téléphone
  (`MediaQuery.padding.bottom`) : le dernier élément n'est jamais caché dessous. Une `ListView` à
  qui l'on donne un `padding` n'ajoute plus cette place toute seule : il faut passer par
  `pageBottomPadding` (ou `pageContentPadding`).
- **Formulaires** (connexion, inscription, mot de passe oublié, connexion d'une TV) : 8 entre le
  titre et sa phrase, 24 avant les champs et avant le bouton, 16 entre deux champs, 12 entre deux
  boutons.
- À l'intérieur d'un bloc (titre, note et genres d'une grande image, contenu d'une carte), les
  petits écarts entre deux lignes d'un même texte (2 à 10) suivent le texte, pas ce tableau.

À ne pas faire : des marges au hasard (14, 18, 22, 28…) dans une page. Si une valeur manque, on
l'ajoute à l'échelle ici et dans `design.dart`. Des tests vérifient les valeurs et les alignements
(`test/design_test.dart`).

## 6. Pages principales

### En-tête de page (`VxPageHeader`)

Recherche, Ma liste et Mes avis commencent toutes par le même en-tête, donc avec les mêmes
espacements. Un test le vérifie (`test/design_test.dart`) :

```
↕ 16 (TV 24)
Titre de page                      28 (TV 56), Sora 700
↕ 16 (TV 24)
[ Champ de recherche ]             largeur max. 720 (TV 1100), pleine largeur sur téléphone
↕ 12 (TV 18)
( Tout ) ( Films ) ( Séries ) …    FilterBar : défile à l'horizontale, avec la marge de page
↕ 16 (TV 24)
Contenu                            pageContentPadding(context)
```

- Marges à gauche et à droite : `layout.gutter`.
- Le contenu sous l'en-tête (grille, liste) prend `pageContentPadding(context)` : la marge de page
  sur les côtés, rien en haut (16 sur TV, pour le zoom du focus) et, en bas, 32 plus la place de la
  barre d'onglets.

### Navigation

- **Téléphone** : une barre d'onglets flottante en bas (pilule de 50 px de haut, flou), avec
  Accueil, Recherche, TV, Ma liste, Avis et l'avatar du profil. Le contenu passe dessous :
  `MediaQuery.padding.bottom` comprend les 66 px de la barre.
- **Tablette, ordinateur, TV** : un rail à gauche, avec l'avatar puis les icônes (Recherche,
  Accueil, Ma liste, Avis, Chaînes TV). L'icône active est verte sur fond vert à 12 %.

- **Rail sur un écran bas** (téléphone tenu à l'horizontale, petite tablette) : les icônes et les
  marges rétrécissent pour que tout reste visible (icône de 40 au minimum) ; si cela ne suffit
  pas, le rail défile, avec une barre de défilement (`_Rail`, `app_shell.dart`).
- **Titre de rangée** (`SectionHeader`) : avec `onSeeAll`, un bouton rond à flèche (28, TV 48) à
  droite du titre ouvre la liste entière (libellé « Voir tout : … » pour les lecteurs d'écran).
- **Changement de page** : toute nouvelle page apparaît en **fondu** (300 ms, sans glissement),
  et repart en fondu au retour ; onglets compris. Réglé une fois pour toutes dans le thème
  (`VxFadePageTransitionsBuilder`, `vxFadeTransition`, `core/theme.dart`).

### Pages principales sans recherche

« Paramètres » (onglet du profil) commence par le même `VxPageHeader` (titre seul), puis
`pageContentPadding` : son titre est à la même place que celui de Recherche, Ma liste et Mes avis.

### Pages secondaires

Les pages secondaires (Paramètres du profil, compte, appareils, connexions, Mon avis, contrôle
parental, code PIN) utilisent `InfoPage`, ou `InfoBody` sous leur propre barre de titre :
- une barre de titre ;
- une colonne de lecture centrée (720 au plus), aux marges de page, 8 (TV 12) sous la barre ;
- **tout est aligné sur les bords de la colonne** : texte d'introduction (`InfoIntro`), titres
  de section (`InfoSection`), cartes. Pas de retrait de 12 pour les textes ;
- des cartes `VxCard` (marge intérieure 20, TV 30), espacées comme des sections (24, TV 36) ou
  comme des lignes de liste (12, TV 18) quand elles se répètent (appareils, profils).

## 7. Composants

| Composant | Taille | Forme | Notes |
| --- | --- | --- | --- |
| Bouton `VxButton` | haut. 52 (TV 76) ; dense 40 (TV 56) | rayon 12 (TV 18) | principal (vert), secondaire (blanc 14 %), contour, danger |
| Bouton rond `VxIconAction` | 52 (TV 76) ; dense 40 (TV 56) | cercle | icône seule, libellé pour les lecteurs d'écran ; vert quand actif (Ma liste, Vu, Noter) |
| Puce `FilterChipButton` | haut. 36 (TV 60) | pilule | contour `lineStrong` ; choisie : fond vert 14 %, texte vert ; flèche si elle ouvre une liste |
| Barre de filtres `FilterBar` | — | — | puces espacées de 8 (TV 14), défile à l'horizontale |
| Champ de recherche `VxSearchField` | texte 16 (TV 24) | pilule (rayon 28) | loupe à gauche, croix pour effacer |
| Champ de saisie | haut. 52 | rayon 12 | fond `field`, bordure `line`, verte au focus, rouge en erreur |
| Carte `VxCard` | marge intérieure 20 (TV 30) | rayon 20 (TV 28) | fond `surface`, bordure `surfaceHigh` |
| Fenêtre (`Dialog`) | largeur max. 480 | rayon 28 | fond `surface`, boutons en colonne sur téléphone |
| Badge `VxBadge` | texte 12 (TV 18) | rayon 0,4 × texte | contour pour l'âge (« 12+ »), plein pour « Nouveau » |
| Alerte `showVxSnack` | — | — | confirme chaque action (« Ajouté à votre liste », « Note enregistrée : 8/10 ») |
| État vide `EmptyState` | icône 44, titre 20 | — | une phrase qui dit quoi faire, et un bouton si une action existe |
| Note TMDb `TmdbRating` | taille du texte autour | — | étoile verte, note, petit logo TMDb (0,7 × la taille du texte) |

## 8. Cartes de titres, rangées et grilles

- **Affiche** : 2:3, rayon 8,6 % de la largeur (10 px environ). **Image horizontale** : 16:9, rayon
  5 %. Le format suit le réglage du profil (`poster_format`).
- **Largeurs** des cartes dans une rangée (`rowCardWidth`) :
  - affiche : 116 (tablette 140, TV 220) ;
  - horizontale : 220 (tablette 260, TV 384).
- **Grilles** (`posterGridDelegate`) : 10 entre les cartes (TV 28).
- **Pas de nom sur l'image des cartes** : l'image suffit. Le nom n'est écrit que pour un titre sans
  image ; il reste dans le libellé pour les lecteurs d'écran.
- **Sur téléphone**, sous chaque affiche (rangées et grilles) : le titre sur une ligne (13,
  semi-gras), puis sur la ligne suivante l'année à gauche et la note TMDb avec son logo à droite
  (11, texte secondaire). Tablette et TV : l'image seule.
- **Logo sur une image horizontale** :
  - il est demandé à la taille d'une carte (`MediaItem.cardLogoUrl`, w300) ;
  - l'image et le logo apparaissent ensemble, une fois les deux chargés (`ImagesTogether`) : le
    logo n'arrive jamais après l'image ;
  - les titres d'une page arrivent avec leur logo (accueil, recherche) ou en une seule requête
    (`/catalog/titles` : Ma liste), jamais avec une requête de fiche par carte.
- **Tailles TMDb à demander** :
  - affiche : w342 ;
  - fond d'une carte : w780 ;
  - grande image et fiche : w1280 ou `original` ;
  - logo : w300 sur une carte, w500 dans la grande image ;
  - image d'épisode : w300.

## 9. Focus et télécommande (`VxFocusable`)

- Tout ce qui se presse passe par `VxFocusable`, et seul ce qui se presse prend le focus.
- Le focus se voit par un anneau de 3,5 px (vert, ou blanc sur un élément vert) et un léger zoom :
  1,06 sur une carte, 1,04 sur un bouton.
- Chaque écran donne le focus à un seul élément à l'arrivée (`autofocus`).
- Les rangées et les barres de filtres sont dans un `FocusTraversalGroup`.
- Sur Android TV, `VxFocusable` recentre automatiquement l'élément sélectionné dans ses zones de défilement (rangée horizontale et page verticale), avec une animation courte. Le même comportement s'applique aux paramètres, listes, grilles et rangées sans logique propre à chaque écran.
- Sur TV, la place du zoom est prévue au-dessus des grilles (16 en haut) et autour des rangées.

## 10. Logo

- Le V blanc, le triangle vert le long de sa branche droite, puis « Vixeo » en Sora ExtraBold :
  `VxLogo(size: …)` dans l'appli (`size` : taille du mot ; le logo fait environ 4,7 × `size` de
  large). Fichiers, proportions et favicon : `brand/README.md`.
- Toujours sur un fond sombre (`background` ou `surface`). Le symbole seul sert d'icône : favicon,
  icônes de l'appli (web, Android, iOS) ; la bannière Android TV montre le logo complet. Le site
  et l'API utilisent les mêmes fichiers.

## 11. Icônes et images

- **Icônes** : Material « rounded ». Contour quand l'élément est inactif, plein quand il est actif
  (`bookmark_add_outlined` puis `bookmark_added_rounded`).
- **Images** : `NetImage` (cache, couleur de remplacement `VxColors.tone(id)` pendant le chargement,
  repli si l'image manque).

## 12. Accessibilité

- Chaque bouton à icône seule a un libellé (`semanticLabel`).
- Les blocs d'informations ont un libellé complet, par exemple `TmdbRating` lu « Note TMDb : 7,1
  sur 10 » ou un QR code décrit.
- Les zones tactiles font au moins 44 px.
- Les couleurs qui doivent se distinguer diffèrent aussi par leur clarté.

## 13. Ajouter un écran : la liste à vérifier

1. Page principale : `VxPageHeader` (titre, recherche, `FilterBar`), puis `pageContentPadding`.
   Page secondaire : `InfoPage` et `VxCard`.
2. Aucune couleur écrite en dur : `VxColors`. Aucune marge hors de l'échelle : `layout.space`.
3. Les tailles ont leur valeur TV : `layout.size(téléphone, tv: …)`.
4. Composants communs (`VxButton`, `VxIconAction`, `FilterChipButton`, `VxSearchField`, `EmptyState`)
   plutôt qu'une version à soi.
5. Un élément a l'`autofocus`, et tout ce qui se presse passe par `VxFocusable`.
6. Vérifier sur téléphone (390 × 844) et sur grand écran (1920 × 1080).

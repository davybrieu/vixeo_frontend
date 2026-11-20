# Logos des sites de notes

Logos affichés à côté des notes (`RatingLogo`, `lib/features/ratings/rating_view.dart`), un par
source de « Source des notes » (`RatingSource`). Ce sont des **marques de leurs propriétaires**,
utilisées seulement pour dire d'où vient une note.

| Fichier | Site | Origine |
| --- | --- | --- |
| `imdb.svg` | IMDb | lettres de l'icône Simple Icons, en noir sur la plaque jaune `#F5C518` |
| `tomatoes.svg` | Rotten Tomatoes (critiques) | icône Simple Icons, rouge `#FA320A` |
| `audience.svg` | Rotten Tomatoes (public) | icône « popcorn » de Lucide (licence ISC, `assets/licenses/lucide-ISC.txt`), rouge `#FA320A` |
| `metacritic.svg` | Metacritic | icône Simple Icons, en blanc (fond sombre) |
| `letterboxd.svg` | Letterboxd | les trois points de l'icône Simple Icons, aux couleurs du site |
| `trakt.svg` | Trakt | icône Simple Icons, violet `#9F42C6` |
| `mal.svg` | MyAnimeList | lettres de l'icône Simple Icons, en blanc sur le bleu `#2E51A2` |

TMDb garde son logo officiel (`assets/images/tmdb_short.png`, `TmdbLogo`).

Simple Icons : paquet npm `simple-icons` 16.38.0 (CC0 1.0 pour les tracés). Lucide : paquet npm
`lucide-static` 1.77.0 (ISC, licence dans « Licences » de l'appli).

## Régénérer les PNG

```bash
pip install cairosvg
python3 brand/tools/rating_logos.py   # → assets/images/ratings/*.png, 128 px de haut
```

Le script écrit le rapport largeur / hauteur de chaque logo : c'est `RatingSource.logoAspect`
(`lib/features/ratings/rating_source.dart`), à mettre à jour si un logo change de forme. Le nom
du fichier est celui de la source (`RatingSource.name`).

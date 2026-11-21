# Logo d'IMDb

Logo affiché à côté des notes d'IMDb (`RatingLogo`, `lib/features/ratings/rating_view.dart`). C'est
une **marque de son propriétaire**, utilisée seulement pour dire d'où vient une note. TMDb garde
son logo officiel (`assets/images/tmdb_short.png`, `TmdbLogo`).

| Fichier | Site | Origine |
| --- | --- | --- |
| `imdb.svg` | IMDb | lettres de l'icône Simple Icons, en noir sur la plaque jaune `#F5C518` |

Simple Icons : paquet npm `simple-icons` 16.38.0 (CC0 1.0 pour les tracés).

## Régénérer le PNG

```bash
pip install cairosvg
python3 brand/tools/rating_logos.py   # → assets/images/ratings/imdb.png, 128 px de haut
```

Le script écrit le rapport largeur / hauteur du logo : c'est `RatingLogo.imdbAspectRatio`, à
mettre à jour si le logo change de forme.

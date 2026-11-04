# Vixeo — appli

Appli Flutter de Vixeo (web, Android, Android TV, iOS), reliée à l'API
[`vixeo_backend`](https://github.com/davybrieu/vixeo_backend).

## Démarrer

```bash
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:8000
```

- API locale : `php artisan serve` dans `vixeo_backend`, avec
  `CORS_ALLOWED_ORIGINS` contenant l'adresse de l'appli web (ex. `http://localhost:8080`).
- Émulateur Android : `--dart-define=API_URL=http://10.0.2.2:8000`.
- Tests : `flutter test` · analyse : `flutter analyze`.

## Écrans

| Écran | Téléphone | TV / grand écran |
| - | - | - |
| Connexion (page d'entrée) | formulaire sur mur d'affiches | carte centrée |
| Inscription | ✓ | ✓ |
| Qui regarde ? | grille, PIN, ajout | rangée, focus télécommande |
| Accueil, Films, Séries | carrousel, rangées, onglets en bas | grande image qui suit le focus, rail à gauche |
| Fiche film / série | ✓ | ✓ |
| Recherche, genres | ✓ | ✓ |
| Ma liste | ✓ | ✓ |

## Web en production

URL sans `#` : le serveur doit renvoyer `index.html` pour les chemins inconnus (Nginx :
`try_files $uri $uri/ /index.html;`).

Voir [`CLAUDE.md`](CLAUDE.md) pour l'architecture et les conventions.

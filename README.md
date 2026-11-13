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

## Version Release (web, Android, iOS)

Une version Release refuse de démarrer s'il lui manque l'un de ces réglages
(`lib/core/config.dart`, `lib/core/legal.dart`) :

```bash
flutter build web --release \
  --dart-define=API_URL=https://api.<domaine> \
  --dart-define=PUBLISHER_NAME="<éditeur : nom de la société ou de la personne>" \
  --dart-define=SUPPORT_EMAIL=support@<domaine>
# iOS (sur un Mac) : flutter build ipa --release avec les mêmes --dart-define
```

- `API_URL` doit être en `https://` (le `http://` n'est accepté que vers `localhost` ou
  l'émulateur Android, pour les tests).
- `PUBLISHER_NAME` et `SUPPORT_EMAIL` s'affichent dans la politique de confidentialité et dans
  « Aide et à propos ».
- Notarisation Apple et distribution web dans l'UE : voir
  [`APPLE_NOTARIZATION.md`](APPLE_NOTARIZATION.md).

## Publier une nouvelle version (Android, iOS)

1. Si besoin, changer la version affichée : `version:` dans `pubspec.yaml` (ex. `1.1.0`). Le numéro
   de build, lui, est donné par la CI (numéro du run, toujours croissant).
2. Pousser sur `main` : la CI compile l'APK signé avec la clé de release et le publie en release
   GitHub `android-<n>`. L'API la lit seule et la propose aux applis (pas de Play Store, pas de
   commande à lancer). Pas d'appli iOS pour l'instant.
3. Pour obliger les versions plus anciennes à se mettre à jour : ajouter `[obligatoire]` au titre
   de la release sur GitHub.

Étapes détaillées (clé de release, empreinte, vérification des développeurs Google) :
[`docs/android-release.md`](docs/android-release.md).

Les applis installées vérifient au lancement, puis toutes les 6 h au plus. Elles proposent la
nouvelle version, ou bloquent si elle est obligatoire (`vixeo_backend/docs/mise-a-jour.md`).

## Écrans

| Écran | Téléphone | TV / grand écran |
| - | - | - |
| Connexion (page d'entrée) | formulaire sur mur d'affiches | carte centrée |
| Inscription | ✓ | ✓ |
| Qui regarde ? | grille, PIN, ajout | rangée, focus télécommande |
| Accueil | carrousel, rangées, onglets en bas | grande image qui suit le focus, rail à gauche |
| Fiche film / série | ✓ | ✓ |
| Recherche, genres | ✓ | ✓ |
| Ma liste | ✓ | ✓ |
| Mot de passe oublié (code par e-mail) | ✓ | ✓ |
| Mon profil : compte, appareils connectés, contrôle parental | ✓ | ✓ |
| Confidentialité, Aide et à propos (sans compte) | ✓ | ✓ |

## Web en production

URL sans `#` : le serveur doit renvoyer `index.html` pour les chemins inconnus (Nginx :
`try_files $uri $uri/ /index.html;`).

Voir [`CLAUDE.md`](CLAUDE.md) pour l'architecture et les conventions.

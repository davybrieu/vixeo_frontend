# Vixeo — appli

Appli Flutter de Vixeo (Android, Android TV, Windows, puis iOS ; plus de version web), reliée à l'API
[`vixeo_backend`](https://github.com/davybrieu/vixeo_backend).

## Démarrer

```bash
flutter pub get
flutter run -d windows --dart-define=API_URL=http://localhost:8000
```

- API locale : `php artisan serve` dans `vixeo_backend`.
- Émulateur Android : `--dart-define=API_URL=http://10.0.2.2:8000`.
- Tests : `flutter test` · analyse : `flutter analyze`.

## Version Release (Android, Windows, iOS)

Une version Release refuse de démarrer s'il lui manque l'un de ces réglages
(`lib/core/config.dart`, `lib/core/legal.dart`) :

```bash
flutter build windows --release \
  --dart-define=API_URL=https://api.<domaine> \
  --dart-define=PUBLISHER_NAME="<éditeur : nom de la société ou de la personne>" \
  --dart-define=SUPPORT_EMAIL=support@<domaine>
# Android : flutter build apk --release ; iOS (sur un Mac) : flutter build ipa --release,
# avec les mêmes --dart-define
```

- `API_URL` doit être en `https://` (le `http://` n'est accepté que vers `localhost` ou
  l'émulateur Android, pour les tests).
- `PUBLISHER_NAME` et `SUPPORT_EMAIL` s'affichent dans la politique de confidentialité et dans
  « Aide et à propos ».
- Notarisation Apple et distribution web dans l'UE : voir
  [`APPLE_NOTARIZATION.md`](APPLE_NOTARIZATION.md).

## Publier une nouvelle version (Android, Windows)

1. Si besoin, changer la version affichée : `version:` dans `pubspec.yaml` (ex. `1.1.0`). Le numéro
   de build, lui, est donné par la CI (numéro du run + 400, toujours croissant).
2. Pousser sur `main` : la CI compile l'APK signé avec la clé de release et l'installateur
   Windows, et les publie en releases GitHub `android-<n>` et `windows-<n>`. L'API les lit seule
   et les propose aux applis et sur le site (pas de store, pas de commande à lancer). Pas d'appli
   iOS pour l'instant.
3. Pour obliger les versions plus anciennes à se mettre à jour : ajouter `[obligatoire]` au titre
   de la release sur GitHub.

Étapes détaillées : [`docs/android-release.md`](docs/android-release.md) (clé de release,
empreinte, vérification des développeurs Google) et
[`docs/windows-release.md`](docs/windows-release.md) (installateur, mise à jour, signature).

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

Voir [`CLAUDE.md`](CLAUDE.md) pour l'architecture et les conventions.

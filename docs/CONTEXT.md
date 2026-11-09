Contexte projet : Vixeo

«Ce document sert de point de départ à une nouvelle session Claude Code.
Il décrit les décisions prises, l'architecture visée, l'environnement technique et les prochaines étapes du projet.

Les décisions marquées « décidé » ne sont pas à rediscuter sans raison. Celles marquées « à valider » sont des pistes à étudier.»

---

1. Le développeur

- Développeur PHP / Laravel et JavaScript / Vue.
- Débutant en Flutter et Dart : expliquer les concepts Flutter lorsqu'ils apparaissent (widgets, état, focus, plateformes) et faire le parallèle avec Vue/Laravel lorsque c'est utile.
- Langue de travail : français (échanges, commentaires de PR, UI).
- Le code (noms de variables, classes, commits) peut rester en anglais.
- Travaille principalement via Claude Code cloud (navigateur et application mobile), donc sans écran sur la machine de build.
- Le rendu doit être vérifié via des URL de prévisualisation (voir §8).

---

2. Objectif produit

Créer une application multiplateforme de type « media center », avec une seule base de code pour :

- Web.
- Android (téléphone et tablette).
- Android TV / Google TV (navigation à la télécommande).
- Chromebook (via APK Android ou version web).
- iOS (et éventuellement Apple TV plus tard).

Priorité absolue : l'esthétique et la fluidité. Interface sur mesure soignée, inspirée des plateformes de streaming, animations fluides, y compris sur les petites box TV.

Fonctionnalités visées

- Écran des sources organisé en onglets (ex. Films/Séries, TV en direct).
- Accueil avec grand carrousel mis en avant et rangées thématiques.
- Section « Continuer à regarder » en tête, avec barre de progression et reprise exacte.
- Fiches film / série :
  - Note, année, durée, genres.
  - Synopsis.
  - Distribution (acteurs cliquables vers leur filmographie).
  - Bande-annonce.
  - Saisons et épisodes.
  - Suggestions similaires (« Vous pourriez aussi aimer »).
  - Métadonnées via TMDb.
- Recherche globale sur les contenus, résultats organisés par catégorie, historique des recherches et raccourcis par genre.
- Lecteur vidéo :
  - Plusieurs flux possibles par contenu.
  - Choix du flux.
  - Bascule automatique en cas d'échec.
  - Flux favoris (❤) essayés en premier.
  - Qualité automatique.
  - Pistes audio et sous-titres.
  - Vitesse de lecture de 0,5× à 2×.
  - Verrouillage des commandes.
  - Picture-in-Picture.
  - Chromecast.
  - Ouverture dans un lecteur externe (VLC, MX Player) avec reprise de position.
  - Fonction « Passer l'intro ».
  - Lecture automatique de l'épisode suivant.
- TV en direct :
  - Affichage des chaînes disponibles.
  - Organisation par catégories.
  - Chaînes favorites.
  - Guide des programmes (EPG) si disponible.
  - Interface adaptée à la navigation TV.
- Profils (« Qui regarde ? ») :
  - Favoris indépendants.
  - Historique indépendant.
  - Reprise de lecture indépendante.
  - Téléchargements indépendants.
- Favoris avec filtres (films, séries, épisodes, vus…) et tris (récent, A→Z, année…).
- Appui long partout = menu contextuel :
  - Ajouter/retirer des favoris.
  - Marquer comme vu.
  - Marquer comme vu jusqu'ici.
  - Retirer de « Continuer à regarder ».
- Sur TV : appui long sur OK pour afficher le menu contextuel.
- Contrôle parental :
  - Code PIN.
  - Âge maximum.
  - Sources et dossiers verrouillés.
  - Recherche respectant les restrictions.
- Sauvegarde et synchronisation entre appareils via un compte utilisateur côté API.
- Mode léger automatique pour les appareils peu puissants (voir §5.7).
- Thèmes, fond d'écran personnalisable et mode immersif.

---

3. API et services externes

3.1 Métadonnées : TMDb

- Utilisation de l'API TMDb pour les films, séries, acteurs, genres, images et autres métadonnées.

- Attribution obligatoire :
  
  « This product uses the TMDB API but is not endorsed or certified by TMDB. »

3.2 Sous-titres : OpenSubtitles

- Utilisation d'OpenSubtitles avec la clé API Vixeo.
- Le backend Laravel interroge OpenSubtitles pour les applications.
- Les fichiers récupérés sont convertis en WebVTT si nécessaire et conservés en cache.
- Langue préférée définie dans le profil utilisateur.
- Détails techniques dans "docs/lecture.md".

3.3 Moments à passer : TheIntroDB

- Utilisation de TheIntroDB pour récupérer les moments à passer (génériques, résumés, intros, etc.), lorsque les données sont disponibles.

3.4 Principe général

Toutes les intégrations externes sont gérées exclusivement par le backend Laravel.

Le frontend Flutter ne communique jamais directement avec ces services, sauf décision technique explicitement justifiée.

---

4. Stack et organisation (décidé)

4.1 Client : Flutter (Dart) — décidé

Utilisation du canal stable de Flutter.

Raisons :

- Moteur de rendu unique.
- Rendu cohérent sur les différentes plateformes.
- Animations fluides.
- Une seule base de code pour mobile, TV, web et desktop.
- Dart accessible depuis une expérience JavaScript/PHP.

Pistes de paquets — à valider :

Besoin| Piste
Gestion d'état| Riverpod
Navigation| go_router
HTTP| dio
Base locale (mobile + web)| drift
Stockage sécurisé des jetons| flutter_secure_storage (moins sécurisé sur le web)
Vidéo| video_player (officiel : ExoPlayer / AVPlayer / HTML5) ; évaluer media_kit pour la largeur de codecs
Lecture HLS sur le web| Lecteur basé sur hls.js si nécessaire
Navigation D-pad TV| Focus, FocusTraversalGroup, Shortcuts / Actions + paquet dpad à évaluer
Chromecast| Plugin communautaire à évaluer
Client API| Généré depuis la spec OpenAPI de Laravel (ex. openapi-generator, générateur dart-dio)

4.2 Backend : Laravel (API REST) — décidé

- Dernière version stable de Laravel.
- PHP 8.3+.
- API versionnée : "/api/v1/...".
- Authentification par jetons avec Laravel Sanctum.
- Base de données PostgreSQL ou MySQL.
- Redis pour le cache et les files d'attente.

OpenAPI :

- Génération automatique de la documentation OpenAPI via Scramble.
- La documentation OpenAPI constitue la source de vérité du contrat API.
- Le client Dart est généré à partir de cette spécification.

Responsabilités du backend :

- Gestion des comptes et profils.
- Synchronisation des favoris, historiques, réglages et progressions.
- Gestion intégrale des serveurs et des configurations de contenus.
- Communication avec les services et API externes.
- Recherche et récupération des contenus.
- Récupération et normalisation des flux disponibles.
- Gestion des erreurs et indisponibilités.
- Cache des métadonnées TMDb.
- Gestion des sous-titres OpenSubtitles.
- Gestion des moments à passer via TheIntroDB.
- Configuration distante (listes de contenus, chaînes, catégories, etc.) modifiable sans republier l'application.
- Gestion des données nécessaires à la TV en direct.

Le backend est entièrement responsable de la logique métier et des traitements nécessaires à la récupération des contenus et des flux.

Pour le frontend, le fonctionnement interne du backend doit rester totalement transparent.

Pour la version web, un proxy de flux côté serveur pourra être nécessaire pour les flux qui exigent des en-têtes HTTP ou ne disposent pas de CORS.

Attention au coût en bande passante et aux ressources serveur si le backend relaie directement les vidéos.

4.3 Dépôts : deux dépôts séparés — décidé

- "vixeo_frontend" : application Flutter.
- "vixeo_backend" : API Laravel.

Chaque dépôt dispose de son propre "CLAUDE.md" contenant :

- Commandes de test et de build.
- Conventions de développement.
- Architecture du projet.
- Lien vers l'autre dépôt.

Pour une fonctionnalité qui touche les deux dépôts :

- Ouvrir une session Claude Code cloud avec les deux dépôts.
- Développer les modifications nécessaires.
- Créer une PR dans chacun des dépôts.

4.4 Hébergement : Laravel Forge + GitHub Actions — décidé

Détails en §8.

---

5. Architecture frontend et lecteur vidéo

5.1 Principe architectural fondamental

Flutter communique exclusivement avec l'API Laravel de Vixeo.

Le frontend ne doit connaître aucune information concernant les mécanismes internes de récupération des contenus.

Il ne doit notamment pas connaître :

- Les fournisseurs de contenus.
- Les serveurs utilisés.
- Les protocoles de communication internes.
- Les méthodes de recherche.
- Les méthodes de récupération ou d'extraction.
- Les API externes utilisées pour récupérer les flux.

Toutes ces responsabilités appartiennent exclusivement au backend Laravel.

Fonctionnement :

1. Flutter effectue une requête HTTP vers l'API Vixeo.
2. Le backend traite la demande.
3. Le backend effectue les opérations nécessaires en interne.
4. Laravel retourne une réponse JSON normalisée.
5. Flutter exploite les données reçues et les affiche.
6. Lorsque l'utilisateur sélectionne un contenu, Flutter utilise les informations de lecture retournées par l'API.

Architecture :

┌──────────────────────────────┐
│           Flutter            │
│                              │
│  Interface utilisateur       │
│  Recherche                   │
│  Catalogue                   │
│  Gestion des interactions    │
│  Lecteur vidéo               │
└──────────────┬───────────────┘
               │
               │ Requêtes HTTP
               ▼
┌──────────────────────────────┐
│         Laravel API          │
│                              │
│  Authentification            │
│  Traitement des demandes     │
│  Recherche des contenus      │
│  Récupération des flux       │
│  Normalisation des données   │
│  Gestion des erreurs         │
└──────────────┬───────────────┘
               │
               │ Traitements internes
               ▼
┌──────────────────────────────┐
│       Services backend       │
│                              │
│  Gestion des serveurs        │
│  Services externes           │
│  Récupération des flux       │
│  Traitement des résultats    │
└──────────────────────────────┘
               │
               ▼
┌──────────────────────────────┐
│        Réponse JSON          │
│                              │
│  Données normalisées         │
│  Flux disponibles            │
│  Métadonnées utiles          │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│           Flutter            │
│                              │
│  Affichage des résultats     │
│  Sélection du flux           │
│  Lecture vidéo               │
└──────────────────────────────┘

Le frontend doit uniquement connaître les endpoints et les structures de données définis dans la documentation OpenAPI.

5.2 Communication avec l'API et chargement des résultats

Lorsqu'une recherche de contenus ou de flux est effectuée :

- Flutter envoie une requête à l'API Vixeo.
- Le backend traite la demande et effectue les opérations nécessaires.
- Les résultats sont retournés sous forme de données JSON normalisées.
- Flutter affiche les résultats reçus.
- L'interface doit pouvoir afficher les premiers résultats disponibles sans attendre inutilement les traitements secondaires, si le contrat API prévoit une réponse progressive.
- Les erreurs sont traitées et présentées clairement à l'utilisateur.

Le mécanisme de communication progressive (SSE, streaming HTTP ou autre) reste à définir selon les contraintes techniques.

Si aucun résultat n'est disponible, afficher un message clair :

« Aucune source disponible pour ce contenu. »

Important : Flutter ne doit jamais reproduire les traitements internes du backend pour obtenir les résultats.

5.3 Tri des options de lecture

Ordre de priorité :

1. Flux favoris de l'utilisateur (❤).
2. Dernier flux ayant fonctionné pour ce contenu.
3. Langue préférée (ex. VF, puis VOSTFR, puis VO).
4. Qualité vidéo.

Mémoriser le dernier flux fonctionnel par contenu et par profil.

Le frontend applique les préférences utilisateur aux résultats normalisés reçus du backend.

5.4 Bascule automatique en cas d'erreur

Classer les erreurs du lecteur et réagir :

Erreur| Réaction
Format / codec non supporté| Essayer le flux suivant, sinon proposer un lecteur externe
Réseau / DNS| Nouvel essai
Lien expiré (HTTP 403)| Demander au backend de nouvelles informations de lecture
Délai dépassé| Essayer le flux suivant
Plus aucun flux disponible| Afficher « Connexion impossible »
Direct (chaîne TV)| Relancer la lecture ou demander de nouvelles informations de lecture au backend

Garder :

- Un cache des flux en échec pour les écarter plus rapidement.
- Un cache des résolutions avec durée de vie, si nécessaire.
- Un historique des flux fonctionnels par contenu.

5.5 Lecteur vidéo

Fonctionnalités attendues :

- Couche HTTP adaptée.
- Gestion des en-têtes nécessaires à la lecture, selon les informations retournées par l'API.
- Détection HLS / DASH / MP4.
- Sous-titres externes attachés au média.
- Gestion des pistes audio.
- Sélection de la qualité.
- Vitesse de lecture de 0,5× à 2×.
- Picture-in-Picture.
- Verrouillage des commandes.
- Chromecast.
- Lecteur externe (VLC, MX Player).
- Reprise de lecture après retour d'un lecteur externe.
- Passage automatique à l'épisode suivant.
- Fonction « Passer l'intro ».

DRM uniquement pour les services qui le fournissent avec le compte de l'utilisateur.

Lecteur externe :

- Envoyer l'URL et les informations de lecture au lecteur externe.
- Demander un résultat lorsque la plateforme le permet.
- Récupérer la position de lecture au retour.
- Sauvegarder la progression.

Chromecast :

- Le Chromecast ne peut pas toujours transmettre les en-têtes HTTP nécessaires.
- Évaluer un mini serveur HTTP local sur le réseau Wi-Fi qui relaie le flux avec les bons en-têtes, si nécessaire.

5.6 Données locales et reprise de lecture

Les données de lecture sont conservées localement et synchronisées avec le backend.

Champs utiles :

- "lastPlaybackPositionMillis"
- "durationMillis"
- "lastEngagementTimeUtcMillis"
- "isWatched"
- "watchedDate"

Règles :

- « Continuer à regarder » = éléments avec "lastEngagement" non nul.
- Trier par dernière activité.
- Film terminé = marqué comme vu.
- Pour les séries : afficher un bandeau « Épisode suivant ».
- La progression doit être indépendante par profil.
- Synchroniser les données entre appareils via l'API.

5.7 Mode léger

Activé automatiquement si :

- La RAM totale est inférieure à environ 1,7 Go.
- Ou la mémoire disponible par application ("memory class") est inférieure ou égale à 128 Mo.

Le mode léger doit pouvoir être désactivé dans les réglages.

Effets :

- Réduire le nombre de requêtes parallèles.
- Réduire la mémoire tampon du lecteur.
- Libérer les écrans et caches inutilisés.
- Limiter les animations coûteuses.
- Éviter les chargements simultanés trop importants.

5.8 Sous-titres

- Recherche OpenSubtitles via l'API Laravel.
- Utilisation de la clé API Vixeo.
- Conversion des fichiers en WebVTT si nécessaire.
- Mise en cache des fichiers.
- Langue préférée définie dans le profil.
- Traduction sur l'appareil (ex. ML Kit de Google).

Fonction avancée à envisager plus tard : calage automatique des sous-titres à partir de l'audio décodé du film (et non du microphone), avec détection des passages parlés.

5.9 Démarrage de l'application

Séquence souhaitée :

1. Détection ou choix de l'interface (TV / mobile).
2. Initialisations en arrière-plan (réseau, caches, Chromecast différé).
3. Après environ 30 minutes d'inactivité : retour à l'écran des sources et redemande du profil.
4. Sélection du profil.
5. Ouverture de la dernière source utilisée, si disponible.
6. Sinon, affichage de l'écran des sources.
7. Vérification des mises à jour (pour une distribution hors store).

---

6. Sécurité

Principes à respecter :

Risque| À faire
Identifiants sensibles stockés en clair| "flutter_secure_storage" (Keystore / Keychain) ; préférer les jetons aux mots de passe
Données sensibles envoyées en JSON lisible| Synchronisation via le compte utilisateur de l'API et chiffrement des données sensibles
Sauvegarde chiffrée avec une clé fixe identique pour tous| Clé dérivée d'un secret utilisateur (Argon2 / PBKDF2), ou exclusion des secrets de la sauvegarde
Vérification des certificats TLS désactivée| Ne jamais désactiver la vérification TLS
Interrupteur à distance bloquant l'application sans explication| Mode maintenance transparent, sans bloquer les fonctions locales
Permissions trop larges| Demander chaque permission uniquement au moment où elle est nécessaire

Points positifs à conserver :

- Aucun SDK publicitaire.
- Aucun SDK de pistage.
- Rapports de plantage envoyés uniquement si l'utilisateur le décide.
- Si des statistiques sont ajoutées : consentement explicite conformément au RGPD.

---

7. Environnement Claude Code cloud

7.1 Environnement

- Sessions lancées depuis "claude.ai/code" ou l'onglet Code de l'application Claude.
- Machine Ubuntu 24.04 temporaire.
- Environ 4 vCPU, 16 Go RAM et 30 Go de disque.
- Préinstallés :
  - PHP 8.3 + Composer.
  - Node 20 / 21 / 22.
  - PostgreSQL 16.
  - Redis 7.
  - Docker.
  - Git.
  - GitHub CLI ("gh").
  - jq.

PostgreSQL et Redis ne tournent pas par défaut :

service postgresql start
service redis-server start

7.2 Installation de Flutter

Flutter n'est pas préinstallé.

Utiliser un environnement cloud dédié « flutter » avec accès réseau Trusted autorisant :

- GitHub.
- pub.dev.
- storage.googleapis.com.

Script à utiliser dans « Setup script » :

#!/bin/bash
set -euo pipefail

FLUTTER_DIR=/opt/flutter

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

git config --global --add safe.directory "$FLUTTER_DIR"

ln -sf "$FLUTTER_DIR/bin/flutter" /usr/local/bin/flutter
ln -sf "$FLUTTER_DIR/bin/dart" /usr/local/bin/dart

export CI=true

flutter --disable-analytics || true
flutter config --no-cli-animations --enable-web
flutter precache --web --no-android --no-ios
flutter --version

État :

- Le clone a été testé.
- La version Flutter est correctement détectée.
- Le téléchargement du SDK Dart depuis "storage.googleapis.com" reste à valider dans l'environnement d'origine.

7.3 Secrets

Ne jamais placer de clés de déploiement dans les variables de l'environnement cloud, car elles sont accessibles à la session.

Utiliser les secrets GitHub.

7.4 Prévisualisation

La machine cloud ne dispose pas d'écran.

Le rendu doit être vérifié via :

- URL de staging.
- URL de prévisualisation de PR.
- Site de production si nécessaire.

Claude peut également surveiller les PR et corriger les échecs de CI ou les commentaires de revue.

---

8. CI/CD et hébergement

8.1 API Laravel sur Forge

Configuration du site Forge :

- Type : General PHP / Laravel.
- Dépôt : "vixeo_backend".
- Branche : "main".
- Push to deploy : activé.
- Zero-downtime deployments : activé.

Script de déploiement utilisant les macros Forge :

- "$CREATE_RELEASE()"
- "$ACTIVATE_RELEASE()"
- "$RESTART_QUEUES()"

Étapes :

- "composer install --no-dev"
- Migrations : "php artisan migrate --force"
- Mise en cache des configurations et routes.
- Redémarrage des workers si nécessaire.

Limite Forge : un déploiement est interrompu au-delà de 10 minutes.

CORS :

- Autoriser le domaine Flutter web.
- Autoriser le domaine de staging.

8.2 Flutter web sur Forge

Ne pas compiler sur le serveur Forge.

GitHub Actions compile Flutter web puis publie uniquement "build/web" sur une branche "web-dist".

Configuration du site Forge :

- Type : Static HTML site.
- Dépôt : "vixeo_frontend".
- Branche : "web-dist".
- Web Directory : "/".
- Push to deploy : activé.
- Zero-downtime deployments : activé.

Si l'application utilise des URL sans "#" ("usePathUrlStrategy"), Nginx doit renvoyer vers "index.html" :

try_files $uri $uri/ /index.html;

8.3 Workflow GitHub Actions

Fichier : ".github/workflows/deploy-web.yml"

name: Flutter web (Forge)

on:
  pull_request:
  push:
    branches: [main]

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get

      - run: flutter test

      - run: flutter build web --release --dart-define=API_URL=${{ vars.API_URL }}

      - name: Publier le build sur la branche web-dist
        if: github.event_name == 'push'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          cd build/web
          git init -q -b web-dist
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -qm "Build web ${GITHUB_SHA::7}"
          git push -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" web-dist

Variable GitHub à définir :

- "API_URL"

8.4 Prévisualisations

Forge ne crée pas automatiquement d'URL par PR.

Trois solutions envisagées :

1. Site Forge de staging

- Déployer une branche "staging".
- Solution la plus simple.

2. Firebase Hosting

- Utiliser Firebase Hosting uniquement pour les prévisualisations de PR.
- Action : "FirebaseExtended/action-hosting-deploy@v0".
- URL commentée automatiquement sur la PR.
- Expiration : 7 jours.
- Secrets :
  - "FIREBASE_SERVICE_ACCOUNT"
  - Variable : "FIREBASE_PROJECT_ID".

Configuration "firebase.json" :

{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}

3. forge-previewer

- Outil tiers de Kirschbaum.
- Crée un site Forge par PR.
- Vérifier sa compatibilité avec la version actuelle de Forge avant utilisation.

8.5 Applications mobiles

Android :

- Pas de Play Store (décision du développeur).
- APK signé avec une clé de release stable, conservée hors du dépôt.
- Distribution depuis le site Vixeo.
- Mises à jour via la vérification intégrée :
  "GET /app/update".

iOS :

- Distribution à définir.
- Une solution de distribution web Apple est envisagée, mais les modalités techniques restent à étudier.

---

9. Conventions de développement

- Code (noms de variables, classes, commits) en anglais.
- Échanges et interface utilisateur en français.
- API versionnée "/api/v1".
- Aucun breaking change dans la v1.
- OpenAPI généré avec Scramble = contrat de référence du client Dart.
- Tests backend avec Pest.
- Formatage backend avec Pint.
- Secrets jamais dans le dépôt ni dans les variables cloud visibles.
- Privilégier les solutions simples et maintenables.
- Éviter les packages inutiles.
- Expliquer les concepts Flutter et Dart au développeur lorsqu'ils apparaissent.
- Toujours prendre en compte les performances des appareils Android TV peu puissants.

Règle fondamentale concernant le frontend

Le frontend Flutter doit rester indépendant de l'implémentation interne du backend.

Il doit uniquement :

- Effectuer des requêtes HTTP vers l'API Vixeo.
- Envoyer les paramètres nécessaires aux recherches.
- Recevoir des réponses JSON normalisées.
- Afficher les données reçues.
- Gérer les interactions utilisateur.
- Lancer la lecture des flux retournés.
- Gérer les préférences et la progression de lecture.

Toute nouvelle intégration externe ou modification des mécanismes de récupération doit être réalisée côté backend, sans imposer de modification frontend tant que le contrat API reste identique.

---

10. Feuille de route suggérée (MVP)

Étape 1 — Base de l'application

- Comptes utilisateurs.
- Profils.
- Synchronisation.
- Catalogue TMDb.
- Lecteur VOD.

État : fait.

Étape 2 — TV en direct

- Récupération des chaînes via l'API Vixeo.
- Affichage des catégories.
- Gestion des favoris.
- Interface TV Hub.
- Navigation optimisée à la télécommande.

Étape 3 — Amélioration du lecteur

- Gestion avancée des flux.
- Bascule automatique.
- Favoris de flux.
- Gestion avancée des pistes audio et sous-titres.
- Chromecast.
- Lecteur externe.
- Optimisation des performances.

Étape 4 — EPG et personnalisation

- Guide électronique des programmes.
- Favoris des chaînes.
- Dossiers personnalisés.
- Mode léger affiné.
- Synchronisation avancée entre appareils.

---

11. Consignes pour Claude Code

Lorsqu'une nouvelle session Claude Code démarre :

1. Lire intégralement ce document.
2. Lire le "CLAUDE.md" du dépôt concerné.
3. Examiner l'architecture existante avant de proposer des modifications.
4. Respecter les décisions déjà prises.
5. Ne pas réintroduire d'anciennes architectures ou fonctionnalités supprimées.
6. Ne pas ajouter de dépendances sans raison valable.
7. Privilégier les implémentations simples et performantes.
8. Vérifier les tests avant de considérer une fonctionnalité comme terminée.
9. Pour les modifications frontend, fournir une URL de prévisualisation lorsque possible.
10. Pour les modifications backend, vérifier la compatibilité avec le contrat OpenAPI.
11. Pour les fonctionnalités touchant les deux dépôts, coordonner les changements et maintenir la compatibilité entre les deux PR.
12. Toujours garder à l'esprit que l'esthétique, la fluidité et l'expérience TV sont des priorités absolues.
13. Ne jamais implémenter de logique spécifique aux fournisseurs ou aux mécanismes de récupération dans Flutter.
14. Toute récupération de contenus doit passer par l'API Vixeo.
15. Ne jamais effectuer directement d'appels aux services externes depuis Flutter lorsque ces opérations relèvent du backend.
16. Considérer l'API Laravel comme l'unique contrat de communication entre le frontend et le backend.
17. Ne pas exposer à l'utilisateur les détails techniques internes de récupération des contenus.
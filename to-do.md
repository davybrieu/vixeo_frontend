# Vixeo : à faire

Liste mise à jour le 5 novembre 2026, pour les trois dépôts : `vixeo_frontend` (appli),
`vixeo_backend` (API) et `vixeo_web` (site). Cocher au fur et à mesure.

Les décisions déjà prises (pas de Play Store, pas d'IPTV / M3U / Xtream, ni de radio ou de replays,
travail sur `main`, pas de workflow GitHub Actions pour l'API) sont dans les `CLAUDE.md`.

---

## 1. Avant la mise en ligne

### Android (APK, sans Play Store)

- [ ] Créer la **clé de release** et la sauvegarder hors de l'ordinateur (gestionnaire de mots de
      passe et copie de secours). Sans elle, aucune mise à jour n'est possible.
      → `vixeo_frontend/docs/android-release.md` §1
- [ ] Créer `android/key.properties` sur le poste qui compile, ou les variables `VIXEO_KEYSTORE_*`
      en CI.
- [ ] S'enregistrer dans l'**Android Developer Console** de Google et y déclarer `app.vixeo.vixeo`
      et sa clé. C'est obligatoire hors Play Store dans 4 pays depuis le 30/09/2026, et prévu
      partout (France comprise) en 2027.
- [ ] Première version : augmenter le build dans `pubspec.yaml` et pousser sur `main` ; la CI
      publie la release GitHub `android-<build>` (APK et SHA-256), que l'API et le site lisent.

### Tests sur de vrais appareils (impossibles dans le conteneur cloud)

- [ ] **Compiler** l'APK Release : la configuration Gradle, `MainActivity.kt`, le `FileProvider`
      et la dépendance `androidx.core` n'ont jamais été compilés.
- [ ] **Téléphone Android** :
  - [ ] installer l'APK depuis le site ;
  - [ ] se connecter, puis parcourir accueil, fiche, recherche, Ma liste ;
  - [ ] profils, contrôle parental, mot de passe oublié ;
  - [ ] suppression et export du compte.
- [ ] **Mise à jour intégrée** :
  - [ ] publier une version 2 ;
  - [ ] vérifier la proposition, le téléchargement et la demande de permission « Installer des
        applis inconnues » ;
  - [ ] vérifier la confirmation d'Android et le redémarrage ;
  - [ ] vérifier qu'un APK signé avec une autre clé est refusé ;
  - [ ] vérifier l'écran « Mise à jour nécessaire » (`--required`).
- [ ] **Android TV / Google TV** :
  - [ ] installer l'APK avec une appli de téléchargement (lien court `/apk`) ;
  - [ ] naviguer à la télécommande (focus vert, flèches, OK, retour) ;
  - [ ] se connecter par QR code depuis le téléphone ;
  - [ ] mise à jour intégrée sur TV ;
  - [ ] grande image : logos des titres, fond, lisibilité à 3 m.
- [ ] **Navigateurs** : appli web sur Chrome, Edge, Firefox et Safari ; site `vixeo_web` sur
      téléphone, tablette et ordinateur.

### Serveurs (Laravel Forge)

- [ ] Choisir les domaines :
  - [ ] l'API (`api.…`) ;
  - [ ] l'appli web (`app.…`, adresse des QR codes `/tv`) ;
  - [ ] le site (domaine principal).
- [ ] **API** : site Forge, PostgreSQL, Redis, file d'attente, planificateur (`schedule:run`).
      Variables : `WEB_URL`, `SITE_URL`, `CORS_ALLOWED_ORIGINS` (limité aux domaines Vixeo),
      `TMDB_READ_ACCESS_TOKEN`, `SANCTUM_EXPIRATION`, `APP_LOCALE=fr`.
      → `vixeo_backend/docs/deploiement.md`
- [ ] **Jeton TMDb de production** : en générer un nouveau sur TMDb (celui des essais a été écrit
      dans une conversation), le mettre seulement dans Forge (`TMDB_READ_ACCESS_TOKEN`), puis vider
      le cache de l'API (`php artisan cache:clear`).
- [ ] **OpenSubtitles** : créer le compte Vixeo et une clé « consumer » sur opensubtitles.com, les
      mettre dans Forge (`OPENSUBTITLES_API_KEY`, `OPENSUBTITLES_USERNAME`, `OPENSUBTITLES_PASSWORD`) ;
      vérifier le quota quotidien de téléchargements (offre VIP ou commerciale pour une appli
      publique) et tester la recherche et le téléchargement avec la vraie clé.
- [ ] **TheIntroDB** : vérifier les conditions d'utilisation des données (non publiées) ; clé
      facultative (`THEINTRODB_API_KEY`) si 5 000 requêtes par jour ne suffisent plus.
- [ ] **Service d'e-mails** (`MAIL_*`, adresse d'envoi vérifiée SPF / DKIM). Sans lui, « Mot de
      passe oublié » et l'export des données ne fonctionnent pas.
- [ ] **Site `vixeo_web`** : site Forge sans base, daemon SSR `php artisan inertia:start-ssr`,
      dossier `public/telechargements/`. → `vixeo_web/docs/deploiement.md`
- [ ] **Appli web** : publier `flutter build web` (workflow `deploy-web.yml` du `docs/CONTEXT.md`
      §8.2, pas encore fait). Nginx : `try_files … /index.html`, et pas de cache sur `index.html`,
      `flutter_bootstrap.js` et `main.dart.js`.
- [ ] HTTPS partout (Let's Encrypt), redirection HTTP → HTTPS et en-tête HSTS.
- [ ] Compiler l'appli avec `API_URL` en https, `PUBLISHER_NAME` et `SUPPORT_EMAIL` : sans ces
      réglages, une version Release refuse de démarrer.

### Légal et textes

- [ ] **Mentions légales du site** : éditeur, adresse, immatriculation, directeur de la
      publication, contact, hébergeur (`VIXEO_PUBLISHER_*`, `VIXEO_HOST_*`).
- [ ] **Relire la politique de confidentialité de l'appli** (`/confidentialite`) : préciser la
      durée des journaux du serveur et le nom de l'hébergeur.
- [ ] Vérifier les **conditions d'utilisation de TMDb** pour l'usage prévu (attribution déjà
      affichée ; usage commercial éventuel).
- [ ] Créer l'adresse de **support** (`SUPPORT_EMAIL`, `VIXEO_CONTACT_EMAIL`).
- [ ] *(Facultatif)* **Notes IMDb** à la place des notes TMDb : seulement avec la licence officielle
      d'IMDb (AWS Data Exchange, contact imdb-licensing-support@imdb.com). Les fichiers gratuits
      d'IMDb et OMDb sont réservés à un usage personnel et non commercial.

---

## 2. Fonctionnalités à développer

- [ ] **Lecteur vidéo et sources** : serveurs personnels Jellyfin, Plex, Emby (le bouton
      « Lecture » affiche pour l'instant « Aucune source disponible »).
- [ ] **Registre des sources** côté API :
  - [ ] statut autorisé / suspendu, base juridique ;
  - [ ] arrêt possible par source et par titre ;
  - [ ] statuts « retiré » (410) et « non autorisé » (451). → `APPLE_NOTARIZATION.md` P13
- [ ] Chaînes FAST seulement avec un accord écrit ou des conditions qui autorisent les applis
      tierces (`docs/CONTEXT.md` §3).
- [x] Historique des recherches synchronisé entre appareils.
- [x] Réglages du profil synchronisés (langue audio et sous-titres préférés, génériques passés
      automatiquement).
- [ ] Lecteur : utiliser les moments à passer (TheIntroDB) et les sous-titres (OpenSubtitles) déjà
      fournis par l'API (`features/playback`, `vixeo_backend/docs/lecture.md`).
- [ ] Résumé en anglais quand le résumé français manque (API).
- [ ] Déverrouillage temporaire d'un titre avec le PIN parental.

---

## 3. iOS (plus tard)

- [ ] Vérifier l'**éligibilité à la distribution web d'Apple** dans l'UE : une organisation, plus
      un critère financier. → `APPLE_NOTARIZATION.md` B1
- [ ] Compiler sur un Mac, tester sur iPhone et iPad (iOS 17.5 ou plus), générer le rapport de
      confidentialité Xcode (valide `PrivacyInfo.xcprivacy`). → P7, P1
- [ ] Compte de démonstration pour la vérification Apple (P12), classification par âge et captures
      4+ (P11).
- [ ] Serveur de distribution web : `/.well-known/marketplace-kit`, adresses `restore` et `updates`,
      jeton d'installation signé, serveur de licences en Swift. → `vixeo_backend/docs/mise-a-jour.md`
- [ ] Autres points de l'audit : version minimale d'iOS (P14), jeton gardé après désinstallation
      (P19).

---

## 4. Qualité et entretien

- [ ] Petites mises à jour de dépendances : `go_router` 18.1.3, dépendances indirectes (P21).
- [ ] Relancer régulièrement `composer audit` (API, site), `npm audit` (site) et la recherche OSV
      (appli).
- [ ] Piste : générer le client Dart depuis `vixeo_backend/docs/openapi.json` au lieu des modèles
      écrits à la main.
- [ ] **Accessibilité** : les boutons Films / Séries de l'accueil (téléphone) et le menu de
      navigation sont lus deux fois par les lecteurs d'écran (« Films Films ») ; même correction que
      les filtres de la recherche (`ExcludeSemantics` sous le libellé).
- [ ] Surveiller la place prise par le cache TMDb dans Redis (images de l'accueil, environ 30 Ko par
      titre, gardées une semaine).
- [ ] Mettre à jour `APPLE_NOTARIZATION.md` et ce fichier à chaque étape franchie.

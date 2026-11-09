# Publier une version Android (APK, sans Play Store)

Vixeo n'est pas sur le Play Store (décision du développeur). L'appli Android (téléphones,
tablettes, Android TV / Google TV) est un **APK signé**, téléchargé depuis le site `vixeo_web`.
Les mises à jour se font depuis l'appli : elle télécharge le nouvel APK, vérifie son empreinte
SHA-256, puis ouvre l'installateur d'Android, qui demande une confirmation.

## 1. La clé de release (une fois pour toutes)

Android n'accepte une mise à jour que si elle est signée avec **la même clé** que la version
installée. Perdre la clé, c'est obliger tout le monde à désinstaller puis réinstaller Vixeo.

```bash
keytool -genkeypair -v -keystore ~/vixeo-release.jks -alias vixeo \
  -keyalg RSA -keysize 4096 -validity 10000
```

- Garder le fichier `.jks` et ses mots de passe dans un gestionnaire de mots de passe, avec une
  sauvegarde hors de l'ordinateur. **Jamais dans le dépôt** : `*.jks`, `*.keystore` et
  `key.properties` sont ignorés par Git.
- Sur le poste qui compile, créer `android/key.properties` :

```properties
storeFile=/chemin/vers/vixeo-release.jks
storePassword=…
keyAlias=vixeo
keyPassword=…
```

- En CI, utiliser plutôt les variables `VIXEO_KEYSTORE_PATH`, `VIXEO_KEYSTORE_PASSWORD`,
  `VIXEO_KEY_ALIAS` et `VIXEO_KEY_PASSWORD`, stockées dans les secrets.

Sans clé, `flutter build apk --release` s'arrête avec un message : un APK signé avec la clé de
débogage ne pourrait jamais être mis à jour.

## 2. Compiler

1. Augmenter `version:` dans `pubspec.yaml` (ex. `1.2.0+14`). Le build, après le `+`, doit
   toujours augmenter.
2. Compiler :

```bash
flutter build apk --release \
  --dart-define=API_URL=https://api.<domaine> \
  --dart-define=PUBLISHER_NAME="…" --dart-define=SUPPORT_EMAIL=support@<domaine>
cp build/app/outputs/flutter-apk/app-release.apk vixeo-1.2.0.apk
sha256sum vixeo-1.2.0.apk
```

Un seul APK sert aux téléphones, aux tablettes et aux TV.

## 3. Publier

La CI s'en charge (`.github/workflows/build-web.yml`) : à chaque poussée sur `main`, elle compile
l'APK signé (clé de release dans les secrets) et le publie en **release GitHub** `android-<n>`,
avec l'APK et son fichier `.apk.sha256`. `<n>` est le numéro du run de la CI, utilisé aussi comme
build de l'APK (`--build-number`) : il augmente tout seul. Le titre de la release reprend la
version de `pubspec.yaml` (« Vixeo Android v1.0.0 - build 160 »). L'API lit ces releases (c'est sa seule source, voir
`vixeo_backend/docs/mise-a-jour.md`) : il n'y a rien à déclarer à la main.

- **Mise à jour obligatoire** (cas sérieux seulement) : sur GitHub, *Releases* → la release →
  *Edit*, ajouter `[obligatoire]` au titre. Les versions plus anciennes affichent alors « Mise à
  jour nécessaire ». Le retirer rend la mise à jour facultative à nouveau.
- **Retirer une version** : supprimer la release, ou la passer en pré-version.
- APK compilé à la main (section 2) : pour qu'il soit proposé, créer une release GitHub avec le
  tag `android-<build>`, l'APK et un fichier `.apk.sha256` contenant son empreinte.

Ensuite, automatiquement (dans les 5 minutes : cache de l'API) :
- les applis installées affichent, à leur prochaine ouverture ou au retour au premier plan, la
  barre « Une nouvelle mise à jour est disponible » avec le bouton « Télécharger » (écran « Mise à
  jour nécessaire » si la release est marquée `[obligatoire]`) ;
- le bouton « Télécharger l'APK » du site pointe vers ce fichier.

## 4. Vérifications sur un appareil

À faire sur un vrai téléphone et une vraie TV : le conteneur Claude Code n'a pas de SDK Android.
- La première mise à jour demande d'autoriser Vixeo à « installer des applis inconnues »
  (réglage d'Android). L'appli ouvre ce réglage, puis on revient appuyer sur « Réessayer ».
- Une mise à jour signée avec une autre clé est refusée par Android.

## 5. Vérification des développeurs par Google

Pour les applis installées hors Play Store, Google exige que le développeur soit enregistré :
- depuis le 30 septembre 2026, dans 4 pays (Brésil, Indonésie, Singapour, Thaïlande) ;
- partout, dont la France, à partir de 2027 (date à suivre).

Il faut créer un compte dans l'**Android Developer Console** et y enregistrer l'appli
(`app.vixeo.vixeo`) et sa clé avant cette date. Sinon, les appareils Android certifiés
refuseront l'installation.

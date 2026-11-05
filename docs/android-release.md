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

1. Déposer le fichier sur le site : `public/telechargements/vixeo-1.2.0.apk` dans `vixeo_web`
   (dossier ignoré par Git, conservé entre les déploiements).
2. Déclarer la version dans l'API (onglet Commands de Forge) :

```bash
php artisan vixeo:release android 1.2.0 14 \
  --apk=https://<domaine>/telechargements/vixeo-1.2.0.apk \
  --sha256=<empreinte> \
  --notes="Nouveautés de la version."
```

Ensuite, automatiquement :
- les applis installées proposent la mise à jour à leur prochaine ouverture (`--required` pour
  l'imposer) ;
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

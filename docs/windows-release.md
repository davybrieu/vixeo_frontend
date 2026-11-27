# Publier une version Windows (installateur, sans Microsoft Store)

Vixeo pour Windows (10 et 11, 64 bits) est distribuée par un **installateur** téléchargé depuis
le site (`www.vixeo.app/#installer`), pas par le Microsoft Store (demande du développeur,
20/11/2026). Les mises à jour se font depuis l'appli, comme sur Android.

## 1. Ce qui est installé

- L'appli Flutter compilée pour Windows (`flutter build windows --release`, dossier
  `build/windows/x64/runner/Release` : `vixeo.exe`, les DLL de Flutter et des plugins, dont
  libmpv pour la lecture (`media_kit_libs_windows_video`), et `data/`).
- L'installateur est fait par **Inno Setup 6** (`windows/installer/vixeo.iss`) :
  - pour **l'utilisateur seulement** (`PrivilegesRequired=lowest`) : dossier
    `%LOCALAPPDATA%\Programs\Vixeo`, **sans droits d'administrateur** ni fenêtre de contrôle de
    compte (UAC) ;
  - raccourci dans le menu Démarrer, icône sur le bureau en option ;
  - désinstallation depuis « Paramètres » → « Applications » ;
  - en français ; 64 bits seulement (`x64compatible`) ;
  - **`AppId` fixe** (`{8C1E0F2A-5B7D-4E2B-9A61-3F2D7C4B9E10}`) : ne jamais le changer, sinon une
    nouvelle version s'installe à côté de l'ancienne au lieu de la remplacer.
- Nom du fichier : `vixeo-setup-<build>.exe`.

## 2. Publier

La CI s'en charge (`.github/workflows/build.yml`, tâche « Build Windows installer and publish
GitHub Release », sur `windows-latest`) : à chaque poussée sur `main`, après l'analyse et les
tests, elle compile l'appli Windows avec le même numéro de build que l'APK (numéro du run + 400, `BUILD_OFFSET`),
fait l'installateur (Inno Setup, installé par `choco` s'il manque) et publie la **release
GitHub** `windows-<build>` (« Vixeo Windows v1.0.0 - build 160 ») avec `vixeo-setup-<build>.exe`
et son fichier `.exe.sha256`.

L'API lit ces releases (`vixeo_backend/docs/mise-a-jour.md`) : le site propose le dernier
installateur et les applis installées voient la mise à jour dans les 5 minutes. **Mise à jour
obligatoire** : ajouter `[obligatoire]` au titre de la release `windows-<build>` sur GitHub.

Compiler à la main (sur un PC Windows avec Flutter et Visual Studio, charge de travail
« Développement Desktop en C++ ») :

```powershell
flutter build windows --release --build-number=<build> `
  --dart-define=API_URL=https://api.vixeo.app `
  --dart-define=PUBLISHER_NAME="…" --dart-define=SUPPORT_EMAIL=support@vixeo.app
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.0 /DBuildNumber=<build> windows\installer\vixeo.iss
```

Le build doit être plus grand que le dernier publié, sinon l'appli ne se croit pas en retard.

## 3. Mise à jour depuis l'appli

`UpdateGate` interroge `GET /app/update?platform=windows&build=<build>` au lancement et au retour
au premier plan (6 h au plus entre deux fois). Quand une version est disponible, la barre « Une
nouvelle mise à jour est disponible » propose « Télécharger » ; une version obligatoire remplace
l'appli par « Mise à jour nécessaire » (« Mettre à jour »).

Le bouton (`ApkInstaller`, `features/updates/apk_installer.dart`) :

1. télécharge `vixeo-setup-<build>.exe` (adresse https de la release, sans le jeton Vixeo) dans
   le dossier temporaire ;
2. vérifie son **SHA-256** (le fichier est supprimé s'il ne correspond pas) ;
3. lance l'installateur en mode silencieux (`/SILENT /SUPPRESSMSGBOXES /NORESTART`), détaché, puis
   **ferme Vixeo** (« Installation de la nouvelle version : Vixeo se ferme, puis redémarre. ») ;
4. l'installateur remplace les fichiers (une petite fenêtre de progression, sans question) et
   **relance Vixeo** à la fin (`[Run]` sans `skipifsilent`).

Sans installateur dans la release, le bouton ouvre la page d'installation du site.

## 4. Signature : pas encore

L'installateur et `vixeo.exe` **ne sont pas signés** (un certificat de signature de code coûte
plusieurs centaines d'euros par an). Conséquence : à la première installation depuis le site,
Windows SmartScreen peut afficher « Windows a protégé votre ordinateur » ; il faut choisir
« Informations complémentaires » puis « Exécuter quand même ». Le site et sa FAQ l'expliquent.
Les mises à jour depuis l'appli ne passent pas par SmartScreen (fichier non marqué « venu
d'Internet »), et l'empreinte SHA-256 est vérifiée.

Pour signer plus tard : un certificat (OV ou EV, ou Azure Trusted Signing), `signtool sign` sur
`vixeo.exe` puis sur l'installateur dans la CI (`SignTool=` d'Inno Setup), le certificat dans les
secrets GitHub, jamais dans le dépôt.

## 5. Ce qui manque sur Windows

- **Notifications appli fermée** : Firebase Cloud Messaging n'existe pas pour une appli Windows, et
  une appli installée sans MSIX ne peut pas recevoir de notification fermée. Les notifications
  (nouveaux épisodes, activité, messages, test) arrivent donc par le **canal temps réel** (Reverb,
  `private-push-devices.{id}`) **tant que Vixeo est ouvert**, et l'appli les affiche en notification
  Windows (`flutter_local_notifications`, AppUserModelID `Vixeo.Vixeo` écrit dans le registre de
  l'utilisateur, effacé par la désinstallation). Il faut la variable GitHub `REVERB_APP_KEY` ; sans
  elle, la page « Notifications » le dit en une phrase. **Pas encore essayé** sur un vrai PC.
- **Connexion TV** : rien à faire sur Windows ; « Connecter une TV » (taper le code d'une TV)
  marche aussi depuis l'ordinateur.
- Plein écran : la fenêtre passe en plein écran (`window_manager`) ; pas d'orientation.

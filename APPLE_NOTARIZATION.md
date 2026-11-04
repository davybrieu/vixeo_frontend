# Vixeo : notarisation Apple (iOS) et distribution web dans l'UE

Audit du 4 novembre 2026, sur `vixeo_frontend` (commit `a8c1ec1`) et `vixeo_backend` (commit `e413624`).
Corrections du même jour : voir le §0.

> **Statut : l'application n'est toujours pas prête pour la notarisation.**
> Restent bloquants :
> - B1 : éligibilité à la distribution web ;
> - P2 : bouton « Lecture » sans lecteur, conservé à la demande du développeur ;
> - P7 : compilation et tests sur iPhone et iPad ;
> - P12 : compte de démonstration ;
> - la configuration d'un service d'e-mails en production.
>
> Aucun point de ce document ne doit être lu comme une déclaration de conformité tant qu'il n'est
> pas marqué « vérifié ».

Légende : ✅ vérifié conforme · ⚠️ à corriger · ❌ bloquant · ❓ non vérifiable dans cet audit

---

## 0. Suivi des corrections (4 novembre 2026)

Corrections validées par le développeur, puis appliquées. Les tableaux des §2 et §3 décrivent l'état
**au moment de l'audit** ; ce suivi les remplace pour les points listés.

| Point | État | Vérification |
|---|---|---|
| P16 Symfony | ✅ Mis à jour en 7.4.23 (`vixeo_backend` `00617d4`) | `composer audit` sans avis ; Pest |
| P3 Mot de passe oublié | ✅ Code à 6 chiffres par e-mail, valable 15 min, usage unique, 5 essais ; les autres appareils sont déconnectés | 9 tests API ; tests de l'appli ; parcours complet dans le navigateur (code lu dans l'e-mail) |
| P5 Suppression et export | ✅ `POST /me/delete` (mot de passe), `POST /me/export` (JSON par e-mail) ; écran « Mon compte » | Tests API (compte, profils, liste, jetons et connexions TV supprimés) ; tests de l'appli ; navigateur (base vide après suppression) |
| P15 Sessions | ✅ Jetons de 180 jours, purge quotidienne, écran « Appareils connectés » | Tests API (expiration, révocation, appareil d'un autre compte refusé) ; navigateur |
| P4 Confidentialité | ✅ Page `/confidentialite`, lisible sans compte (= « Privacy Policy URL » : `<WEB_URL>/confidentialite`), liens sur la connexion, l'inscription et « Mon profil » | ⚠️ Texte juridique **à relire par le développeur** ; préciser la durée des journaux du serveur et l'hébergeur |
| P6 Contact | ✅ « Aide et à propos » (`/a-propos`) : contact, éditeur, version | Une version Release exige `PUBLISHER_NAME` et `SUPPORT_EMAIL` ; ❓ URL de support à renseigner dans App Store Connect |
| P9 Mention TMDb, services tiers | ✅ Mention affichée dans « Aide et à propos » ; TMDb et YouTube décrits dans la politique | Tests de l'appli |
| P7 Démarrage | ✅ Restauration de session : une erreur du trousseau mène à la connexion, une réponse inattendue à « Réessayer » | Tests de l'appli ; ❓ compilation iOS toujours à faire |
| P10 HTTPS | ✅ Une version Release refuse une `API_URL` absente ou non `https://` | Tests de l'appli ; ❓ HSTS et redirection côté Forge (documentés dans `docs/deploiement.md`) |
| P8 Polices | ✅ Sora et Inter intégrées (OFL, licences dans « Licences ») ; `google_fonts` retiré | Plus aucune requête vers Google au lancement |
| P1 Manifeste | ✅ `ios/Runner/PrivacyInfo.xcprivacy`, ajouté aux ressources du projet Xcode | ❓ À confirmer avec le rapport de confidentialité Xcode (P7) |
| P18 Chiffrement | ✅ `ITSAppUsesNonExemptEncryption` = false | ❓ Obligations d'export à confirmer |
| P2 Lecture | ❌ **Inchangé** (décision du développeur) | Reste bloquant pour la règle 2.1(a) |

Reste à faire :
- B1 ;
- P2, P7, P11, P12, P13, P14, P17, P19, P20, P21 ;
- configurer le service d'e-mails en production (`MAIL_*` dans Forge, adresse vérifiée SPF / DKIM).
  Sans lui, « Mot de passe oublié » et l'export des données ne fonctionnent pas.

---

## 1. Méthode et limites de l'audit

- Audit fait dans un conteneur Linux **sans macOS ni Xcode** :
  - aucune compilation iOS ;
  - aucun test sur iPhone ou iPad ;
  - aucun rapport de confidentialité Xcode (*Privacy Report*).
  Tout ce qui en dépend est marqué ❓.
- Contrôles faits :
  - lecture du code (appli Flutter et API Laravel), de `ios/Runner/Info.plist` et du projet Xcode ;
  - vulnérabilités connues des dépendances : base publique [OSV](https://osv.dev) pour les
    paquets Dart, `composer audit` pour l'API ;
  - recherche de secrets, d'URL `http://`, de permissions, de WebView, de *code push*, de SDK de
    suivi ou de publicité ;
  - parcours de bout en bout de l'appli web contre l'API locale (connexion, profils, catalogue,
    QR code TV, contrôle parental).
- Les règles d'Apple ont été relues le 4 novembre 2026 sur les pages officielles (§9). Elles
  changent souvent : relire ces pages avant chaque soumission.

---

## 2. Ce qu'Apple exige (rappel)

### 2.1 Distribution web dans l'UE (*Web Distribution*)

Source : [Web Distribution in the EU](https://developer.apple.com/support/web-distribution-eu/),
[Changes for apps in the EU](https://developer.apple.com/support/apps-in-the-eu/).

- **Éligibilité.** La page parle d'une « organisation », qui doit remplir **au moins un** de ces
  critères :
  - score Dun & Bradstreet de faible risque ;
  - société cotée en bourse, ou filiale d'une société cotée ;
  - financement par un fonds de capital-risque reconnu ;
  - audit financier par un expert-comptable ;
  - exonération de frais (association, établissement scolaire, administration) ;
  - lettre de crédit *stand-by* d'un million de dollars ;
  - plus d'un million de premières installations annuelles dans le monde, avec deux ans
    d'ancienneté dans l'Apple Developer Program.

  Les pages ne disent pas si un développeur individuel peut y accéder. En revanche, une société
  n'a plus besoin d'être établie dans l'UE.
- **Obligations** :
  - ne proposer que ses propres applis ;
  - répondre à Apple en cas de fraude ou de problème de sécurité ;
  - publier une politique transparente sur les données collectées, et laisser aux utilisateurs le
    contrôle de ces données ;
  - respecter le DSA, le RGPD et le droit de la consommation ;
  - traiter les demandes des autorités ;
  - assurer le support client et les remboursements ;
  - déclarer à Apple les transactions de biens numériques.
- **Technique** :
  - l'appli doit être **notarisée** ;
  - elle ne s'installe que depuis un **domaine enregistré dans App Store Connect** ;
  - il faut au minimum **iOS 17.5** (ou iPadOS 18) sur l'appareil ;
  - App Store Connect fournit le paquet signé (*alternative distribution package*), à héberger
    sur le site.
- **Frais** : depuis le 1er octobre 2026, ce sont les conditions unifiées de l'UE (annexe 14 du
  contrat développeur). Elles prévoient une **Core Technology Commission de 5 %** sur les ventes
  de biens numériques. Pour une appli gratuite sans achat, cette commission ne s'applique pas,
  mais il faut tout de même déclarer les transactions.
- **Non documenté** sur les pages lues : la façon dont les **mises à jour** arrivent sur les
  appareils, et les exigences précises pour le serveur web. Elles sont décrites dans la
  documentation MarketplaceKit, que je n'ai pas pu lire (elle a besoin de JavaScript). À relire
  avant de construire le site de distribution.

### 2.2 Notarisation : règles qui s'appliquent

La notarisation vérifie un **sous-ensemble** des [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
Ces règles y sont marquées d'une icône (bouton « Highlight Notarization Review Guidelines Only »).
Les règles marquées qui concernent Vixeo :

| Règle | Exigence | Statut Vixeo |
|---|---|---|
| 1.5 | L'appli et l'URL de support donnent un moyen simple de contacter le développeur | ❌ P6 |
| 1.6 | Sécurité adaptée des données utilisateur | ⚠️ P10, P15, P16 |
| 2.1(a) | Version finale : pas de contenu provisoire, URL fonctionnelles, compte de démonstration si connexion | ❌ P2, P3, P12 |
| 2.3.1(a), 2.3.6, 2.3.7, 2.3.8 | Métadonnées exactes, classification par âge honnête, métadonnées adaptées à un public 4+ | ⚠️ P11 |
| 2.4.2 | Pas de consommation d'énergie inutile | ✅ (rien en tâche de fond) |
| 2.5.1 | API publiques uniquement | ❓ (dépend des plugins, à confirmer à la compilation) |
| 2.5.2 | Appli autonome : ne télécharge ni n'exécute de code qui ajoute ou change des fonctions | ✅ |
| 2.5.3 | Pas de code malveillant | ✅ |
| 2.5.6 | Navigation web via WebKit | ✅ (pas de WebView ; liens ouverts dans les applis du système) |
| 2.5.14 | Consentement explicite pour tout enregistrement d'activité | ✅ (aucun) |
| 2.5.18 | Règles sur la publicité | ✅ (aucune publicité) |
| 2.5.19 | Pas de fonction cachée, dormante ou non documentée | ✅ (aucun interrupteur distant) |
| 4.8 | Connexion tierce → proposer une alternative respectueuse | ✅ (comptes Vixeo uniquement : exemption) |
| 5 / 5.1 | Respect de toutes les lois applicables, vie privée | ⚠️ P4, P5, P8, P9 |
| 5.1.2 | Pas de transmission de données personnelles sans permission | ⚠️ P8, P9 |
| 5.1.4(a) | Applis surtout pour enfants : pas d'analytics ni de publicité tierces | ✅ (aucune) |
| 5.6.2 | Identité du développeur exacte | ❓ (métadonnées App Store Connect) |

Les règles 5.1.1(i) (politique de confidentialité), 5.1.1(v) (suppression du compte) et 5.2
(propriété intellectuelle) ne sont **pas** marquées pour la notarisation. Elles restent
nécessaires pour d'autres raisons :
- les obligations de la distribution web (transparence sur les données, RGPD) ;
- le champ « Privacy Policy URL » d'App Store Connect ;
- la règle 5 (« respecter toutes les lois applicables »), qui, elle, est marquée.

---

## 3. Contrôles effectués

### 3.1 Architecture et sécurité

| Contrôle | Méthode | Résultat |
|---|---|---|
| Aucun code natif ou exécutable téléchargé | Dépendances (`pubspec.lock`) et code : pas de WebView, de *code push* (Shorebird…), d'interpréteur Dart, de `DynamicLibrary.open`, de `Isolate.spawnUri` | ✅ L'API ne renvoie que des données JSON et des URL d'images |
| Aucun contournement des protections iOS | Code et `Info.plist` | ✅ |
| Permissions iOS | `Info.plist` : aucune clé `NS…UsageDescription` (caméra, photos, localisation, micro…) | ✅ Aucune permission demandée |
| HTTPS (App Transport Security) | `Info.plist` : aucune exception ATS | ✅ iOS refuse le HTTP vers des domaines publics |
| HTTPS dans la configuration | `lib/core/config.dart` | ⚠️ P10 : l'adresse par défaut est `http://localhost:8000` |
| Aucun secret dans l'appli | Recherche de clés et jetons | ✅ La clé TMDb n'existe que côté serveur ; `API_URL` n'est pas un secret |
| Stockage de la session | `SecureSessionStorage` | ✅ Jeton dans le trousseau iOS (Keychain) ; le PIN parental n'est gardé qu'en mémoire |
| Aucun secret dans une URL | Test `OpenApiTest` de l'API | ✅ |
| Mots de passe et PIN | API | ✅ Hachés ; limites d'essais (connexion, PIN, codes TV) |
| Jetons de session | `config/sanctum.php` | ⚠️ P15 : n'expirent jamais |
| Vulnérabilités connues | OSV : 96 paquets Dart | ✅ Aucune |
| | `composer audit` (API) | ⚠️ P16 : avis Symfony publiés le 4 novembre 2026 |
| Erreurs réseau | `ApiClient`, `ApiException` | ✅ Délais de 10 s / 20 s, messages en français, « Réessayer » |
| Réponses invalides de l'API | `ApiClient._send`, modèles | ⚠️ Un JSON inattendu produit un message générique avec « Réessayer » (correct), sauf au démarrage : P7 |

### 3.2 API et catalogue

| Contrôle | Résultat |
|---|---|
| Catalogue géré côté serveur | ✅ Tout vient de l'API (TMDb mis en cache, filtré par âge selon le profil) ; rien n'est codé en dur dans l'appli |
| Contenus pour adultes | ✅ `include_adult=false` sur TMDb ; âge maximum par profil (`AgeGate`) |
| Lecture vidéo | ❌ P2 : aucune lecture n'existe (pas de lecteur, pas de source) |
| Contrôle des sources et des droits | ⚠️ P13 : à construire avant toute source de flux (registre côté serveur) |
| Contenus indisponibles / supprimés / non autorisés | ⚠️ P13 : un 404 TMDb devient un 404 de l'API et un message d'erreur, mais aucun statut dédié (retiré, non autorisé) |
| Fonctions masquées pendant la vérification | ✅ Aucun interrupteur distant : `/catalog/config` ne renvoie que la configuration des images |

### 3.3 Confidentialité et transparence

| Contrôle | Résultat |
|---|---|
| Politique de confidentialité accessible depuis l'appli | ❌ P4 : absente |
| Documentation des données collectées | ⚠️ Inventaire au §5 (base de la politique et des « App Privacy » d'App Store Connect) |
| Collecte minimale | ✅ Nom, e-mail, mot de passe, profils et activité de visionnage : rien d'autre ; aucun analytics, aucune publicité, aucun suivi (ATT inutile) |
| Données transmises à des tiers | ⚠️ P8 : polices Google téléchargées au lancement ; P9 : images TMDb, bandes-annonces YouTube |
| Contrôle par l'utilisateur (RGPD) | ❌ P5 : pas de suppression de compte, pas d'export des données |
| Mentions obligatoires | ⚠️ P9 : mention TMDb définie dans le code mais jamais affichée |
| Sessions | ⚠️ P15 : jetons sans expiration, pas de liste des appareils connectés |

### 3.4 Qualité et stabilité iOS

| Contrôle | Résultat |
|---|---|
| Compilation Release iOS, test sur appareil | ❓ P7 : impossible sans Mac ; jamais compilé pour iOS à ce jour |
| Versions iOS ciblées | ⚠️ Cible minimale du projet : iOS 15.0 ; la distribution web exige iOS 17.5 sur l'appareil (P14) |
| Plantage ou blocage au démarrage | ⚠️ P7 : une erreur du trousseau ou une réponse invalide pendant la restauration de session laisse l'écran de démarrage bloqué |
| Cycle de vie (arrière-plan, retour) | ⚠️ Aucune gestion explicite ; sans risque aujourd'hui (pas de lecteur), à traiter avec le lecteur (P2) |
| Conventions iOS | ✅ Pas de comportement système modifié ; orientations standard ; scènes UIKit (Flutter 3.47) |
| Manifeste de confidentialité (`PrivacyInfo.xcprivacy`) | ⚠️ P1 (voir aussi §6) : absent au niveau de l'appli |
| Dépendances et compatibilité iOS | ✅ À jour (§6) ; ❓ compatibilité à confirmer à la compilation |

### 3.5 Préparation à la distribution

| Contrôle | Résultat |
|---|---|
| Éligibilité à la distribution web | ❌ B1 : à vérifier par le développeur (critères au §2.1) |
| Identifiant de l'appli | ✅ `app.vixeo.vixeo` |
| Signature | ⚠️ Signature automatique, équipe (`DEVELOPMENT_TEAM`) non renseignée |
| Version | ⚠️ `1.0.0+1` dans `pubspec.yaml` ; le numéro de build doit augmenter à chaque envoi (P17) |
| Déclaration de chiffrement (*export compliance*) | ⚠️ Clé `ITSAppUsesNonExemptEncryption` absente : App Store Connect posera la question à chaque envoi (P18) |
| Compte de démonstration pour la vérification | ❌ P12 : à créer |
| Domaine de distribution, page d'installation | ❓ À construire (`vixeo_web` pourrait servir) |

---

## 4. Problèmes détectés et actions correctives

Chaque action qui **modifie l'existant** attend l'accord du développeur avant d'être faite.

### 4.1 Bloquants

**B1. Éligibilité à la distribution web (hors code).**
Il faut être une organisation qui remplit un des critères du §2.1.
- Action : vérifier le statut de Vixeo : société ? numéro D-U-N-S et score Dun & Bradstreet ?
  Puis déposer la demande sur
  [developer.apple.com/contact/request/web-distribution-eu](https://developer.apple.com/contact/request/web-distribution-eu/)
  après avoir accepté le dernier contrat développeur.
- Sans éligibilité, la distribution web est impossible. Il reste la soumission à l'App Store
  (vérification complète) ou une boutique alternative (notarisation plus les règles de la
  boutique).

**P2. Bouton « Lecture » sans lecture possible (règle 2.1(a)).**
Sur la fiche et sur les épisodes, « Lecture » affiche « Aucune source disponible… Ajoutez un
serveur Jellyfin, Plex ou Emby ». Or l'appli ne permet pas encore d'ajouter de serveur. Une
vérification Apple y verrait une fonction provisoire.
- Recommandé : implémenter les serveurs personnels (Jellyfin / Plex / Emby) et le lecteur avant la
  soumission, puisque c'est la fonction principale d'un media center.
- Sinon : en attendant, retirer le bouton ou changer son texte.

Fichier : `lib/features/catalog/details_screen.dart`. Retirer une fonction qui n'existe pas
encore ne trompe personne. Il ne faut en revanche jamais cacher une fonction réelle pendant la
vérification.

**P3. Lien « Mot de passe oublié ? » provisoire (règle 2.1(a)).**
Le lien affiche « La réinitialisation du mot de passe arrive bientôt. »
(`lib/features/auth/login_screen.dart`).
- Action : implémenter la réinitialisation (route d'API, e-mail, page de saisie), ou retirer le
  lien d'ici là.

**P4. Pas de politique de confidentialité.**
Elle est obligatoire pour plusieurs raisons :
- les obligations de la distribution web ;
- le RGPD ;
- le champ « Privacy Policy URL » d'App Store Connect.

Actions :
- rédiger la politique d'après le §5 et l'héberger sur le site (par exemple `vixeo_web`) ;
- ajouter un lien dans l'inscription, la connexion et « Mon profil » ;
- ajouter une page « À propos » : version, mention TMDb, licences (`showLicensePage`), contact.

**P5. Pas de suppression de compte ni d'export des données (RGPD, articles 17 et 20).**
La distribution web exige de laisser aux utilisateurs le contrôle de leurs données.
- Côté API : une route `POST /v1/me/delete`, avec mot de passe dans le corps de la requête. Ce
  n'est pas un DELETE, pour respecter la règle « pas de secret sur un DELETE ». Les profils et la
  synchro sont déjà supprimés en cascade. Il faut aussi révoquer tous les jetons.
- Côté API : une route d'export (JSON) des données du compte.
- Côté appli : un bouton « Supprimer mon compte » dans « Mon profil », avec confirmation.

**P6. Aucun moyen de contact dans l'appli (règle 1.5).**
- Action : une entrée « Aide et contact » (adresse e-mail de support) dans « Mon profil » et sur
  la page « À propos ».
- Action : renseigner une URL de support dans App Store Connect.

**P7. Appli jamais compilée ni testée sur iOS.**
- Action : compiler sur un Mac ou dans un CI macOS :
  `flutter build ipa --release --dart-define=API_URL=https://…`.
- Action : tester sur au moins un iPhone sous iOS 17.5 ou plus, et un iPad sous iPadOS 18 ou plus.
- Action : générer le rapport de confidentialité Xcode (Product → Archive → Generate Privacy
  Report).
- Défaut de démarrage trouvé dans le code, à corriger en même temps : `Session.restore()`
  (`lib/features/auth/session.dart`) n'attrape que les `ApiException`. Une erreur du trousseau
  (`PlatformException`) ou une réponse invalide (`TypeError`) laisse l'écran de démarrage en
  chargement **indéfiniment**. Correction : attraper toute erreur et passer à l'état
  « serveur injoignable », qui propose déjà « Réessayer ».

### 4.2 Importants

**P1. Manifeste de confidentialité de l'appli absent.**
Il manque `ios/Runner/PrivacyInfo.xcprivacy`. Les plugins iOS natifs en ont un
(`flutter_secure_storage_darwin`, `url_launcher_ios`, `sqflite_darwin`). En revanche,
`path_provider_foundation` 2.6.0, qui passe par `objective_c` 9.5.0 en FFI, n'en contient pas, et
le cache d'images lit des dates de fichiers.
- Action : ajouter un manifeste au niveau de l'appli. Il déclarerait :
  - `NSPrivacyTracking` = false, sans domaine de suivi ;
  - les types de données collectées (§5) ;
  - les API à justification, par exemple les dates de fichiers dans le conteneur, raison
    `C617.1`.
- Puis confirmer avec le rapport Xcode (P7). ❓ Liste exacte à valider sur Mac.

**P8. Polices téléchargées depuis Google au lancement (règle 5.1.2, RGPD).**
`google_fonts` récupère Sora et Inter sur les serveurs de Google, ce qui leur transmet l'adresse
IP de l'utilisateur sans son accord. Un tribunal allemand l'a jugé contraire au RGPD
(LG München, 2022).
- Action : intégrer les fichiers de police dans l'appli. Sora et Inter sont sous licence OFL, ce
  qui l'autorise.
- Action : désactiver le téléchargement (`GoogleFonts.config.allowRuntimeFetching = false`).

Fichiers : `lib/core/theme.dart`, `pubspec.yaml`.

**P9. Services tiers : à déclarer.**
- Les images viennent directement de `image.tmdb.org`, qui voit donc l'adresse IP de
  l'utilisateur.
- Les bandes-annonces s'ouvrent dans YouTube.
- Les recherches sont transmises à TMDb par le serveur, sans l'identité de l'utilisateur.

Actions :
- déclarer ces services dans la politique de confidentialité ;
- en option, faire passer les images par le serveur Vixeo ;
- afficher la mention TMDb obligatoire (`AppConfig.tmdbAttribution`, jamais affichée
  aujourd'hui) dans « À propos ».

**P10. HTTPS non garanti dans la configuration.**
Une version Release compilée sans `--dart-define=API_URL` vise `http://localhost:8000`.
- Action : refuser de démarrer en Release si `API_URL` ne commence pas par `https://`, et le
  vérifier dans le script de build.
- Côté serveur, à vérifier sur Forge : redirection HTTPS, en-tête HSTS, certificat valide.
  ❓ Non vérifiable ici.

**P11. Classification par âge et métadonnées (règles 2.3.6 et 2.3.8).**
L'appli montre des affiches, des résumés et des bandes-annonces de titres jusqu'à 18 ans.
- Action : répondre honnêtement au questionnaire de classification d'App Store Connect.
- Action : choisir des captures d'écran adaptées à un public 4+ (règle 2.3.8).

**P12. Compte de démonstration pour la vérification (règle 2.1(a)).**
- Action : créer sur l'API de production un compte avec des profils et des données.
- Action : fournir ses identifiants dans « App Review Information ».
- L'API doit rester joignable pendant la vérification.

**P13. Sources de diffusion et droits (avant tout lecteur).**
Une source n'est jamais autorisée simplement parce qu'elle est accessible. À prévoir :
- côté API, un **registre des sources** : type, statut autorisé / suspendu, base juridique
  (contrat, conditions d'utilisation, serveur personnel de l'utilisateur), pays ;
- un arrêt possible **par source et par titre**, sans mise à jour de l'appli ;
- des statuts dédiés : contenu retiré (410), non autorisé dans le pays (451) ;
- côté appli, un message clair pour ces statuts.

À propos des sources prévues :
- les chaînes FAST (Pluto TV, Samsung TV Plus…) seulement avec un accord écrit, ou des conditions
  qui autorisent explicitement les applis tierces ;
- les serveurs personnels (Jellyfin / Plex / Emby) sont sous la responsabilité de l'utilisateur ;
  vérifier les conditions d'utilisation de l'API Plex.

Cf. `docs/CONTEXT.md` §3. La base existe déjà : `locked_sources` par profil.

**P14. Version minimale d'iOS.**
Le projet vise iOS 15.0, mais la distribution web demande iOS 17.5 sur l'appareil.
- Action : ce n'est pas obligatoire. On peut monter la cible à 17.5 pour que la liste des
  appareils à tester corresponde aux appareils qui pourront installer l'appli.

**P15. Jetons de session sans expiration.**
Les jetons n'expirent jamais (`config/sanctum.php`), et on ne peut ni voir ni déconnecter les
appareils (TV comprises).
- Action : une durée de vie, par exemple 180 jours.
- Action : une page « Appareils connectés », avec un bouton pour en retirer.

**P16. Dépendances de l'API à mettre à jour.**
`composer audit` signale des avis publiés le 4 novembre 2026 sur `symfony/http-foundation`,
`symfony/http-kernel` et `symfony/routing` (installés en 7.4.22, corrigés en 7.4.23), dont
CVE-2026-118514 et CVE-2026-118516.
- Action :
  `composer update symfony/http-foundation symfony/http-kernel symfony/routing`, puis Pest et Pint.
  Cela modifie `composer.lock`.

### 4.3 Mineurs

- **P17. Versions.** Augmenter `version:` dans `pubspec.yaml`, ou passer `--build-name` et
  `--build-number` dans le CI, à chaque envoi. Tenir un journal des versions.
- **P18. Déclaration de chiffrement.** L'appli n'utilise que le chiffrement standard (HTTPS,
  trousseau). Ajouter `ITSAppUsesNonExemptEncryption` = false dans `Info.plist`, après
  vérification des obligations d'export applicables.
- **P19. Jeton gardé après désinstallation.** Le trousseau iOS survit à la désinstallation, donc
  l'utilisateur est encore connecté s'il réinstalle l'appli. On peut effacer le jeton au premier
  lancement après une installation.
- **P20. CORS.** Si `CORS_ALLOWED_ORIGINS` n'est pas renseignée, l'API accepte toutes les
  origines. Le risque est faible (jetons Bearer, sans cookie), mais il vaut mieux la régler sur
  `WEB_URL` en production. C'est un réglage, pas du code.
- **P21. Mises à jour mineures.** `go_router` 18.1.3 est disponible ; quelques dépendances
  indirectes aussi (§6).

---

## 5. Données collectées (base de la politique de confidentialité)

| Donnée | Où | Pourquoi | Durée |
|---|---|---|---|
| Nom, adresse e-mail | API (`users`) | Compte | Jusqu'à la suppression du compte (P5) |
| Mot de passe | API, haché | Connexion | Idem |
| PIN parental, PIN de profil | API, hachés | Contrôle parental | Idem |
| Profils (nom, avatar, profil enfant, âge maximum, format des affiches) | API (`profiles`) | Personnalisation, filtre d'âge | Idem |
| Activité : favoris, progression, titres vus (titre, dates) | API (`profile_items`) | Synchro entre appareils, « Continuer à regarder » | Idem |
| Nom de l'appareil (ex. « Vixeo TV ») | API (jetons, connexions TV) | Identifier les sessions | Jetons sans expiration (P15) ; codes TV supprimés un jour après expiration |
| Adresse IP | Limites d'essais (cache), journaux du serveur web | Sécurité | Quelques minutes (cache) ; journaux selon la configuration Forge (à préciser) |
| Termes recherchés | Transmis à TMDb par le serveur, sans identité | Recherche | Non enregistrés par Vixeo |
| Jeton de session, profil choisi | Appareil (trousseau iOS) | Rester connecté | Jusqu'à la déconnexion |
| Cache d'images | Appareil | Performance | Géré par le cache |

Rien d'autre n'est collecté : pas de localisation, de contacts, de photos, d'identifiant
publicitaire, d'analytics ni de rapport de plantage. App Store Connect (« App Privacy ») :
coordonnées (nom, e-mail), identifiants (ID utilisateur), usage (interactions avec le contenu).
Ces données sont liées à l'utilisateur et **ne servent pas au suivi**.

---

## 6. Dépendances

- **Flutter** 3.47.9, Dart 3.13, canal stable.
- **Paquets directs** : `flutter_riverpod` 3.4.3, `go_router` 18.1.2, `dio` 5.11.1,
  `flutter_secure_storage` 11.2.0, `cached_network_image` 4.0.6, `google_fonts` 9.0.0,
  `url_launcher` 6.3.3, `qr_flutter` 4.1.0, `cupertino_icons` 1.0.9.
- **Code natif iOS** (plugins) :

  | Plugin | Version | Manifeste de confidentialité |
  |---|---|---|
  | `flutter_secure_storage_darwin` | 0.4.3 | oui |
  | `url_launcher_ios` | 6.4.2 | oui |
  | `sqflite_darwin` | 2.4.5 | oui |
  | `path_provider_foundation` | 2.6.0 (FFI via `objective_c` 9.5.0) | non trouvé → P1 |

- **Vulnérabilités** :
  - Dart : aucune connue sur 96 paquets (OSV, 4 novembre 2026) ;
  - API : voir P16.
- **Aucun SDK** de publicité, d'analytics, de suivi, de rapport de plantage, de WebView ou de
  *code push*.

---

## 7. Étapes de distribution (une fois les blocages levés)

1. Éligibilité confirmée (B1). Accepter le dernier contrat développeur, puis demander la
   distribution web.
2. Corriger les points P1 à P16. Compiler la version Release sur macOS, la signer (certificat de
   distribution, profil de provisionnement) et la tester sur appareil.
3. Dans App Store Connect :
   - créer l'appli (`app.vixeo.vixeo`) et remplir les métadonnées : description, captures 4+,
     classification par âge, URL de confidentialité et de support, « App Privacy », coordonnées du
     développeur et statut de commerçant (DSA) ;
   - ajouter le domaine de distribution.
4. Envoyer le build (Xcode ou Transporter). Dans « App Review Information », choisir le type
   **Notarization** et fournir le compte de démonstration. Puis soumettre.
5. Une fois l'appli acceptée, récupérer le paquet de distribution et l'héberger sur le domaine
   enregistré, avec la page d'installation (documentation MarketplaceKit, ❓ à relire).
6. Pour chaque mise à jour : nouveau numéro de build, nouvelle notarisation, nouveau paquet.
   La façon dont l'appareil reçoit la mise à jour reste à confirmer (§2.1).

---

## 8. À vérifier sur Mac (non vérifiable dans cet audit)

- Compilation Release iOS, archive, rapport de confidentialité Xcode.
- Démarrage, connexion, navigation et rotation sur iPhone (iOS 17.5 ou plus) et iPad
  (iPadOS 18 ou plus) ; aucun avertissement d'API privée (règle 2.5.1).
- Comportement hors ligne au lancement et au retour d'arrière-plan.
- Configuration HTTPS et HSTS de l'API sur Forge.

---

## 9. Sources (lues le 4 novembre 2026)

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (règles
  marquées pour la notarisation)
- [Web Distribution in the EU](https://developer.apple.com/support/web-distribution-eu/)
- [Changes for apps in the European Union](https://developer.apple.com/support/apps-in-the-eu/)
- [Submit for Notarization (App Store Connect)](https://developer.apple.com/help/app-store-connect/managing-alternative-distribution/submit-for-notarization/)
- [Installation depuis un site web dans l'UE (expérience utilisateur)](https://developer.apple.com/support/alt-distribution-ux-in-the-eu/)
- [OSV](https://osv.dev) (vulnérabilités des paquets Dart), `composer audit` (Packagist / FriendsOfPHP)

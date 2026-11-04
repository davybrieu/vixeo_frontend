import 'package:flutter/material.dart';

import '../../core/legal.dart';
import '../../core/theme.dart';
import 'info_page.dart';

/// Privacy policy (`/confidentialite`), readable without an account: it is also the
/// "Privacy Policy URL" given to Apple (`<WEB_URL>/confidentialite`).
///
/// Keep it in line with what the app and the API really do (APPLE_NOTARIZATION.md §5): a new
/// kind of data or a new service = update this text and [Legal.privacyPolicyDate].
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final contact = Legal.supportEmail.isEmpty
        ? 'l’adresse de support indiquée dans « Aide et à propos »'
        : Legal.supportEmail;

    return InfoPage(
      title: 'Confidentialité',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 8 * s, 12 * s, 16 * s),
          child: Text(
            'Dernière mise à jour : ${Legal.privacyPolicyDate}',
            style: VxText.body(13 * s, color: VxColors.textMuted),
          ),
        ),
        InfoSection(
          title: 'Qui sommes-nous ?',
          autofocus: true,
          children: [
            InfoText(
              'Vixeo est édité par ${Legal.publisherOrDefault}, responsable des données décrites ici. '
              'Pour toute question sur vos données : $contact.',
            ),
          ],
        ),
        const InfoSection(
          title: 'Les données que nous conservons',
          children: [
            InfoBullet(
              'Votre compte : prénom, adresse e-mail et mot de passe. Le mot de passe est enregistré sous forme '
              'hachée : illisible, même pour nous.',
            ),
            InfoBullet(
              'Vos profils : nom, avatar, réglages (profil enfant, âge maximum, format des affiches) et, si vous en '
              'mettez un, le code PIN (lui aussi haché). De même pour le code PIN parental du compte.',
            ),
            InfoBullet(
              'Ce que vous regardez : votre liste, votre progression et les titres marqués comme vus, pour les '
              'retrouver sur tous vos écrans.',
            ),
            InfoBullet(
              'Vos appareils connectés : leur type (par exemple « Vixeo TV »), la date de connexion et de dernière '
              'utilisation.',
            ),
            InfoBullet(
              'Pour la sécurité : votre adresse IP, pendant quelques minutes, pour limiter les tentatives de '
              'connexion, et les journaux techniques du serveur, pendant une durée limitée.',
            ),
            InfoBullet(
              'Pour les mises à jour (Android et iOS) : à chaque ouverture, l’appli envoie à notre serveur sa '
              'plateforme et son numéro de version, sans votre identité. Rien n’est conservé.',
            ),
          ],
        ),
        const InfoSection(
          title: 'Ce que nous ne faisons pas',
          children: [
            InfoText(
              'Pas de publicité, pas de suivi entre applis ou sites, pas de mesure d’audience, pas de revente ni de '
              'partage de vos données à des fins commerciales.',
            ),
            InfoText(
              'Vixeo ne demande accès ni à votre position, ni à vos contacts, ni à vos photos, ni à votre micro, ni à '
              'votre caméra.',
            ),
          ],
        ),
        const InfoSection(
          title: 'Pourquoi nous les utilisons',
          children: [
            InfoBullet(
              'Faire fonctionner votre compte, vos profils et leur synchronisation : c’est le service que vous '
              'demandez (article 6.1.b du RGPD).',
            ),
            InfoBullet(
              'Protéger les comptes contre les abus (limites d’essais, journaux) : notre intérêt légitime '
              '(article 6.1.f du RGPD).',
            ),
          ],
        ),
        const InfoSection(
          title: 'Services tiers',
          children: [
            InfoBullet(
              'TMDb (The Movie Database) fournit les informations et les images des films et séries. Les images '
              'sont chargées directement depuis les serveurs de TMDb, qui reçoivent donc votre adresse IP. Vos '
              'recherches sont transmises à TMDb par notre serveur, sans votre identité.',
            ),
            InfoBullet(
              'YouTube : les bandes-annonces s’ouvrent dans YouTube (application ou site), qui applique sa propre '
              'politique de confidentialité.',
            ),
            InfoBullet(
              'Notre hébergeur et notre service d’envoi d’e-mails (codes de réinitialisation, export de vos '
              'données) traitent vos données uniquement pour notre compte.',
            ),
          ],
        ),
        const InfoSection(
          title: 'Combien de temps',
          children: [
            InfoText(
              'Tant que votre compte existe. Quand vous le supprimez, tout est effacé immédiatement : compte, '
              'profils, liste, progression et appareils.',
            ),
            InfoText(
              'Une connexion d’appareil expire après 180 jours ; un code de réinitialisation, après 15 minutes.',
            ),
          ],
        ),
        InfoSection(
          title: 'Vos droits',
          children: [
            const InfoBullet('Recevoir une copie de vos données : Mon profil → Mon compte → Recevoir mes données.'),
            const InfoBullet(
              'Supprimer votre compte et toutes vos données : Mon profil → Mon compte → Supprimer mon compte.',
            ),
            const InfoBullet('Déconnecter un appareil : Mon profil → Appareils connectés.'),
            InfoBullet('Corriger vos informations ou vous opposer à un traitement : écrivez à $contact.'),
            const InfoText('Vous pouvez aussi adresser une réclamation à la CNIL (www.cnil.fr).'),
          ],
        ),
        const InfoSection(
          title: 'Sécurité',
          children: [
            InfoText(
              'Toutes les communications sont chiffrées (HTTPS). Mots de passe et codes PIN sont hachés. Sur votre '
              'appareil, la session est gardée dans le stockage sécurisé du système (trousseau iOS, Keystore '
              'Android).',
            ),
          ],
        ),
        const InfoSection(
          title: 'Enfants',
          children: [
            InfoText(
              'Les profils enfants sont créés et gérés par le titulaire du compte, qui peut limiter les titres selon '
              'l’âge et protéger ces réglages par un code PIN parental.',
            ),
          ],
        ),
        const InfoSection(
          title: 'Changements',
          children: [InfoText('Cette page est mise à jour à chaque changement ; sa date figure en haut.')],
        ),
      ],
    );
  }
}

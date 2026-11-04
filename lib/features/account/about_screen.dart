import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'info_page.dart';

/// "Aide et à propos" (`/a-propos`), readable without an account: contact, privacy policy,
/// TMDb notice, licences, version.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _writeToSupport(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: Legal.supportEmail, query: 'subject=Vixeo');
    final opened = await launchUrl(uri).catchError((_) => false);
    // No mail app (TV…): the address is written on the page anyway.
    if (!opened && context.mounted) showVxSnack(context, 'Écrivez-nous à ${Legal.supportEmail}.');
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final hasEmail = Legal.supportEmail.isNotEmpty;

    return InfoPage(
      title: 'Aide et à propos',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 8 * s, 12 * s, 20 * s),
          child: Row(
            children: [
              VxLogo(size: 28 * s),
              SizedBox(width: 14 * s),
              Text('Version ${AppConfig.appVersion}', style: VxText.body(15 * s, color: VxColors.textSecondary)),
            ],
          ),
        ),
        InfoSection(
          title: 'Aide et contact',
          children: [
            InfoText(
              hasEmail
                  ? 'Une question, un problème, une demande sur vos données ? Écrivez-nous à ${Legal.supportEmail}.'
                  : 'Une question, un problème, une demande sur vos données ? Contactez l’éditeur de Vixeo.',
            ),
          ],
        ),
        Wrap(
          spacing: 12 * s,
          runSpacing: 12 * s,
          children: [
            if (hasEmail)
              VxButton(
                label: 'Écrire au support',
                icon: Icons.mail_outline_rounded,
                autofocus: true,
                onPressed: () => _writeToSupport(context),
              ),
            VxButton(
              label: 'Politique de confidentialité',
              icon: Icons.privacy_tip_outlined,
              kind: VxButtonKind.outline,
              autofocus: !hasEmail,
              onPressed: () => context.push('/confidentialite'),
            ),
          ],
        ),
        SizedBox(height: 24 * s),
        const InfoSection(
          title: 'Films et séries',
          children: [
            InfoText(
              'Les informations et les images des films et séries viennent de TMDb (The Movie Database), '
              'www.themoviedb.org.',
            ),
            InfoText(AppConfig.tmdbAttribution),
          ],
        ),
        InfoSection(
          title: 'Éditeur',
          children: [InfoText('${Legal.publisherOrDefault}${hasEmail ? ' · ${Legal.supportEmail}' : ''}')],
        ),
        VxButton(
          label: 'Licences des logiciels',
          icon: Icons.description_outlined,
          kind: VxButtonKind.outline,
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'Vixeo', applicationVersion: AppConfig.appVersion),
        ),
      ],
    );
  }
}

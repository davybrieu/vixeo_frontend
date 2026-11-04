import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exception.dart';
import '../../core/config.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../updates/update_gate.dart';
import '../updates/updates.dart';
import 'info_page.dart';

/// "Aide et à propos" (`/a-propos`), readable without an account: contact, privacy policy,
/// TMDb notice, licences, version and updates.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  Future<void> _writeToSupport(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: Legal.supportEmail, query: 'subject=Vixeo');
    final opened = await launchUrl(uri).catchError((_) => false);
    // No mail app (TV…): the address is written on the page anyway.
    if (!opened && context.mounted) showVxSnack(context, 'Écrivez-nous à ${Legal.supportEmail}.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final hasEmail = Legal.supportEmail.isNotEmpty;
    final installed = ref.watch(installedVersionProvider).value;
    final version = installed == null ? '' : '${installed.version} (build ${installed.build})';

    return InfoPage(
      title: 'Aide et à propos',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 8 * s, 12 * s, 20 * s),
          child: Row(
            children: [
              VxLogo(size: 28 * s),
              SizedBox(width: 14 * s),
              Text('Version $version', style: VxText.body(15 * s, color: VxColors.textSecondary)),
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
        if (ref.watch(updatePlatformProvider) != null) ...[const _UpdatesSection(), SizedBox(height: 24 * s)],
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
          onPressed: () => showLicensePage(context: context, applicationName: 'Vixeo', applicationVersion: version),
        ),
      ],
    );
  }
}

/// Android / iOS: state of the last update check, and a button to check now.
class _UpdatesSection extends ConsumerStatefulWidget {
  const _UpdatesSection();

  @override
  ConsumerState<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<_UpdatesSection> {
  bool _checking = false;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final info = await ref.read(updateProvider.notifier).check();
      if (!mounted || info == null) return;
      switch (info.status) {
        case UpdateStatus.upToDate:
          showVxSnack(context, 'Vixeo est à jour.', icon: Icons.check_circle_outline_rounded);
        case UpdateStatus.updateAvailable:
          await showUpdateAvailableDialog(context, info);
        case UpdateStatus.updateRequired:
          break; // The whole app shows "Mise à jour nécessaire".
      }
    } on Object catch (e) {
      if (mounted) showVxSnack(context, e is ApiException ? e.message : 'Vérification impossible.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final info = ref.watch(updateProvider).value;
    final text = switch (info?.status) {
      UpdateStatus.updateAvailable => 'La version ${info!.latest?.version ?? ''} est disponible.',
      UpdateStatus.upToDate => 'Vous avez la dernière version.',
      _ => 'Vixeo vérifie les mises à jour à chaque ouverture.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoSection(title: 'Mises à jour', children: [InfoText(text)]),
        Padding(
          padding: EdgeInsets.only(left: 12 * s),
          child: Wrap(
            spacing: 12 * s,
            runSpacing: 12 * s,
            children: [
              VxButton(
                label: 'Rechercher une mise à jour',
                icon: Icons.refresh_rounded,
                kind: VxButtonKind.outline,
                loading: _checking,
                onPressed: _checkNow,
              ),
              if (info?.status == UpdateStatus.updateAvailable)
                VxButton(
                  label: 'Mettre à jour',
                  icon: Icons.system_update_rounded,
                  onPressed: () => openUpdatePage(context, info!),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

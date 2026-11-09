import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import 'apk_installer.dart';
import 'updates.dart';

/// Opens the install page of the site (no Play Store), when the app can't install the update
/// itself. Android TVs often have no browser: the page address is then shown instead.
Future<bool> openUpdatePage(BuildContext context, UpdateInfo info) async {
  final url = info.updateUrl;
  final uri = url == null ? null : Uri.tryParse(url);
  final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened && context.mounted) {
    final where = url == null ? 'depuis le site de Vixeo' : 'depuis ${url.replaceFirst(RegExp(r'^https?://'), '')}';
    showVxSnack(context, 'Installez la nouvelle version $where.', icon: Icons.system_update_rounded);
  }
  return opened;
}

/// "Télécharger" / "Mettre à jour": on Android, downloads and installs the APK in the app
/// ([updateDownloadProvider]); otherwise (iOS, release without APK) opens the install page.
Future<void> startUpdate(BuildContext context, WidgetRef ref, UpdateInfo info) async {
  final release = info.latest;
  if (ref.read(apkInstallerProvider).canInstall(release)) {
    await ref.read(updateDownloadProvider.notifier).install(release!);
  } else {
    await openUpdatePage(context, info);
  }
}

/// What the last download attempt means for the person (null before it).
String? updateDownloadMessage(UpdateDownload download) => switch (download.result) {
  ApkInstallResult.started => 'Confirmez l’installation dans la fenêtre d’Android : Vixeo redémarre ensuite.',
  ApkInstallResult.permissionNeeded =>
    'Autorisez Vixeo à installer des applis (« Installer des applis inconnues »), revenez ici, puis réessayez.',
  ApkInstallResult.corrupted => 'Le fichier téléchargé est incorrect : il a été supprimé. Réessayez.',
  ApkInstallResult.failed => 'Téléchargement impossible. Vérifiez votre connexion et réessayez.',
  _ => null,
};

/// Download progress, while it runs.
String updateProgressLabel(double? progress) =>
    progress == null ? 'Préparation du téléchargement…' : 'Téléchargement… ${(progress * 100).round()} %';

/// "Mettre à jour" of the blocking screen, with the progress and messages underneath.
class UpdateButton extends ConsumerWidget {
  const UpdateButton({super.key, required this.info, this.autofocus = false, this.expand = false});

  final UpdateInfo info;
  final bool autofocus;
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final download = ref.watch(updateDownloadProvider);
    final message = updateDownloadMessage(download);

    return Column(
      crossAxisAlignment: expand ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (download.busy) ...[
          Text(updateProgressLabel(download.progress), style: VxText.body(14 * s, color: VxColors.textSoft)),
          SizedBox(height: 10 * s),
          ClipRRect(
            borderRadius: BorderRadius.circular(4 * s),
            child: LinearProgressIndicator(
              value: download.progress,
              minHeight: 6 * s,
              color: VxColors.accent,
              backgroundColor: VxColors.surfaceHigh,
            ),
          ),
        ] else ...[
          if (message != null) ...[
            Text(message, style: VxText.body(14 * s, color: VxColors.textSoft)),
            SizedBox(height: 12 * s),
          ],
          VxButton(
            label: download.failed ? 'Réessayer' : 'Mettre à jour',
            icon: download.failed ? Icons.refresh_rounded : Icons.system_update_rounded,
            autofocus: autofocus,
            expand: expand,
            onPressed: () => startUpdate(context, ref, info),
          ),
          if (download.result == ApkInstallResult.failed || download.result == ApkInstallResult.corrupted)
            TextButton(
              onPressed: () => openUpdatePage(context, info),
              child: const Text('Ouvrir la page de téléchargement'),
            ),
        ],
      ],
    );
  }
}

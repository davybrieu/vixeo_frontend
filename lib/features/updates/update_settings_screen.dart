import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import 'update_gate.dart';
import 'updates.dart';

/// Manual update check, available from Settings on supported mobile platforms.
class UpdateSettingsScreen extends ConsumerWidget {
  const UpdateSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = uiScale(context);
    final platform = ref.watch(updatePlatformProvider);
    final installed = ref.watch(installedVersionProvider);
    final update = ref.watch(updateProvider);

    String status;
    if (platform == null) {
      status = 'Cette plateforme reçoit automatiquement la dernière version de Vixeo.';
    } else if (update.isLoading) {
      status = 'Vérification des mises à jour…';
    } else if (update.hasError) {
      status = 'Impossible de vérifier les mises à jour. Vérifiez votre connexion puis réessayez.';
    } else {
      status = switch (update.value?.status) {
        UpdateStatus.updateAvailable => 'Une nouvelle version est disponible.',
        UpdateStatus.updateRequired => 'Une mise à jour est nécessaire pour continuer.',
        UpdateStatus.upToDate => 'Vixeo est à jour.',
        null => 'Aucune information de mise à jour disponible.',
      };
    }

    return InfoPage(
      title: 'Mise à jour',
      fallback: '/profil',
      children: [
        InfoSection(
          title: 'Version installée',
          autofocus: true,
          children: [
            InfoText(installed.when(
              data: (value) => 'Version ${value.version} (${value.build})',
              loading: () => 'Chargement de la version…',
              error: (_, _) => 'Version installée indisponible.',
            )),
            InfoText(status),
          ],
        ),
        if (update.value?.status == UpdateStatus.updateAvailable ||
            update.value?.status == UpdateStatus.updateRequired)
          Padding(
            padding: EdgeInsets.only(left: 12 * scale, bottom: 16 * scale),
            child: UpdateButton(info: update.value!, autofocus: true, expand: true),
          ),
        if (platform != null)
          Padding(
            padding: EdgeInsets.only(left: 12 * scale),
            child: VxButton(
              label: 'Rechercher une mise à jour',
              icon: Icons.refresh_rounded,
              kind: VxButtonKind.secondary,
              onPressed: () async {
                try {
                  final info = await ref.read(updateProvider.notifier).check();
                  if (!context.mounted) return;
                  final message = switch (info?.status) {
                    UpdateStatus.upToDate => 'Vixeo est à jour.',
                    UpdateStatus.updateAvailable => 'Une nouvelle mise à jour est disponible.',
                    UpdateStatus.updateRequired => 'Une mise à jour est nécessaire.',
                    null => 'Aucune information de mise à jour disponible.',
                  };
                  showVxSnack(
                    context,
                    message,
                    icon: info?.status == UpdateStatus.upToDate
                        ? Icons.check_circle_rounded
                        : Icons.system_update_rounded,
                  );
                } catch (_) {
                  if (context.mounted) {
                    showVxSnack(context, 'Vérification impossible. Réessayez plus tard.');
                  }
                }
              },
            ),
          ),
      ],
    );
  }
}

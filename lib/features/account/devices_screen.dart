import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/models.dart' show formatFrenchDate;
import 'info_page.dart';

final devicesProvider = FutureProvider.autoDispose<List<Device>>((ref) => ref.read(authRepositoryProvider).devices());

/// "Appareils connectés" (`/profil/appareils`): every device signed in to the account, and a way
/// to sign one out (a lost phone, an old TV…).
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref, Device device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Déconnecter « ${device.name} » ?'),
        content: Text(
          'Il faudra se reconnecter sur cet appareil pour l’utiliser à nouveau.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(label: 'Déconnecter', autofocus: true, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).revokeDevice(device.id);
      ref.invalidate(devicesProvider);
      if (context.mounted) showVxSnack(context, '« ${device.name} » a été déconnecté.', icon: Icons.logout_rounded);
    } on ApiException catch (e) {
      if (context.mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final devices = ref.watch(devicesProvider);

    return InfoPage(
      title: 'Appareils connectés',
      fallback: '/profil',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 8 * s, 12 * s, 16 * s),
          child: Text(
            'Chaque appareil reste connecté 180 jours. Déconnectez ceux que vous n’utilisez plus ou que vous ne '
            'reconnaissez pas.',
            style: VxText.body(15 * s, color: VxColors.textSecondary),
          ),
        ),
        AsyncView(
          value: devices,
          onRetry: () => ref.invalidate(devicesProvider),
          data: (list) => Column(
            children: [
              for (final (i, device) in list.indexed)
                _DeviceTile(
                  device: device,
                  autofocus: i == 0,
                  onSignOut: device.current
                      ? () => ref.read(sessionProvider.notifier).logout()
                      : () => _signOut(context, ref, device),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onSignOut, this.autofocus = false});

  final Device device;
  final VoidCallback onSignOut;
  final bool autofocus;

  IconData get _icon {
    final name = device.name.toLowerCase();
    if (name.contains('tv')) return Icons.tv_rounded;
    if (name.contains('web') || name.contains('mac') || name.contains('windows')) return Icons.computer_rounded;
    return Icons.smartphone_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final details = [
      if (device.lastUsedAt != null) 'Dernière activité le ${formatFrenchDate(device.lastUsedAt!)}',
      if (device.signedInAt != null) 'connecté le ${formatFrenchDate(device.signedInAt!)}',
      if (device.expiresAt != null) 'jusqu’au ${formatFrenchDate(device.expiresAt!)}',
    ].join(', ');

    // Phones: the button goes under the text, which keeps the full width.
    final phone = Layout.of(context).isPhone;
    final icon = Padding(
      padding: EdgeInsets.only(right: 16 * s),
      child: Icon(_icon, size: 30 * s, color: device.current ? VxColors.accent : VxColors.textSecondary),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10 * s,
          runSpacing: 4 * s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(device.name, style: VxText.title(17 * s)),
            if (device.current) VxBadge('Cet appareil', accent: true, fontSize: 12 * s),
          ],
        ),
        if (details.isNotEmpty) ...[
          SizedBox(height: 4 * s),
          Text(details, style: VxText.body(13 * s, color: VxColors.textSecondary)),
        ],
      ],
    );
    final button = VxButton(
      label: device.current ? 'Se déconnecter' : 'Déconnecter',
      kind: VxButtonKind.outline,
      autofocus: autofocus,
      onPressed: onSignOut,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: 12 * s),
      child: Material(
        color: VxColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18 * s),
          side: const BorderSide(color: VxColors.surfaceHigh),
        ),
        child: Padding(
          padding: EdgeInsets.all(16 * s),
          child: phone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        Expanded(child: text),
                      ],
                    ),
                    SizedBox(height: 12 * s),
                    Align(alignment: Alignment.centerRight, child: button),
                  ],
                )
              : Row(
                  children: [
                    icon,
                    Expanded(child: text),
                    SizedBox(width: 12 * s),
                    button,
                  ],
                ),
        ),
      ),
    );
  }
}

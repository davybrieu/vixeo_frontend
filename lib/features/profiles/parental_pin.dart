import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../auth/session.dart';
import 'pin_pad.dart';

// Parental PIN of the account (vixeo_backend/docs/controle-parental.md). It is set in « Mon compte »
// (`ParentalPinSection`) and asked, on the keypad, to create or delete a profile and to change its
// restrictions (« Gérer les profils », `askParentalPin`). The former « Contrôle parental » and
// « Code PIN » pages are gone (demande du développeur).

/// The parental PIN, checked by the API, or null when the person closes the keypad. Null at once
/// without parental control (nothing to ask).
Future<String?> askParentalPin(BuildContext context, WidgetRef ref, {required String reason}) async {
  if (!(ref.read(sessionProvider).user?.parentalControl ?? false)) return null;
  return showPinPad(
    context,
    title: 'Code PIN parental',
    subtitle: reason,
    onSubmit: (pin) async {
      try {
        await ref.read(authRepositoryProvider).verifyParentalPin(pin);
        return null;
      } on ApiException catch (e) {
        return e.field('pin') ?? e.message;
      }
    },
  );
}

/// « Code PIN parental » in « Mon compte »: « Activer » without a code; « Changer le code »,
/// « Désactiver » and « Code oublié ? » (the account password) with one. Codes are typed on the
/// keypad of the profiles (`showPinPad`).
class ParentalPinSection extends ConsumerStatefulWidget {
  const ParentalPinSection({super.key});

  @override
  ConsumerState<ParentalPinSection> createState() => _ParentalPinSectionState();
}

class _ParentalPinSectionState extends ConsumerState<ParentalPinSection> {
  @override
  void initState() {
    super.initState();
    // The status may have changed on another device.
    ref.read(sessionProvider.notifier).refreshUser().ignore();
  }

  void _done(String message, IconData icon) {
    if (mounted) showVxSnack(context, message, icon: icon);
  }

  Future<String?> _newPin({String? current}) => showPinPad(
    context,
    title: 'Code PIN parental',
    subtitle: 'Choisissez un code à 4 chiffres',
    confirm: true,
    onSubmit: (pin) async {
      try {
        await ref.read(authRepositoryProvider).setParentalPin(pin, currentPin: current);
        return null;
      } on ApiException catch (e) {
        return e.field('pin') ?? e.field('current_pin') ?? e.message;
      }
    },
  );

  Future<void> _enable() async {
    if (await _newPin() == null) return;
    await ref.read(sessionProvider.notifier).refreshUser();
    _done('Contrôle parental activé', Icons.shield_rounded);
  }

  Future<void> _change() async {
    final current = await askParentalPin(context, ref, reason: 'Saisissez le code actuel');
    if (current == null || !mounted) return;
    if (await _newPin(current: current) == null) return;
    _done('Code PIN parental modifié', Icons.shield_rounded);
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Désactiver le contrôle parental ?'),
        content: Text(
          'Tout le monde pourra créer des profils et retirer les restrictions.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(label: 'Désactiver', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final pin = await showPinPad(
      context,
      title: 'Code PIN parental',
      subtitle: 'Saisissez le code actuel',
      onSubmit: (pin) async {
        try {
          await ref.read(authRepositoryProvider).disableParentalControl(currentPin: pin);
          return null;
        } on ApiException catch (e) {
          return e.field('current_pin') ?? e.field('pin') ?? e.message;
        }
      },
    );
    if (pin == null) return;
    await ref.read(sessionProvider.notifier).refreshUser();
    _done('Contrôle parental désactivé', Icons.lock_open_rounded);
  }

  Future<void> _forgot() async {
    final password = await showDialog<String>(context: context, builder: (_) => const ParentalPasswordDialog());
    if (password == null || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).disableParentalControl(password: password);
      await ref.read(sessionProvider.notifier).refreshUser();
      _done('Contrôle parental désactivé. Vous pouvez définir un nouveau code.', Icons.lock_open_rounded);
    } on ApiException catch (e) {
      _done(e.field('password') ?? e.message, Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final enabled = ref.watch(sessionProvider.select((s) => s.user?.parentalControl ?? false));
    return InfoSection(
      title: 'Code PIN parental',
      children: [
        InfoText(
          enabled
              ? 'Le code est demandé pour créer ou supprimer un profil et pour modifier ses restrictions.'
              : 'Protégez les profils : le code sera demandé pour les créer, les supprimer ou changer leurs '
                    'restrictions.',
        ),
        SizedBox(height: layout.space(VxSpace.xs)),
        Wrap(
          spacing: 12 * s,
          runSpacing: 12 * s,
          children: enabled
              ? [
                  VxButton(
                    label: 'Changer le code',
                    icon: Icons.password_rounded,
                    kind: VxButtonKind.secondary,
                    onPressed: _change,
                  ),
                  VxButton(label: 'Désactiver', kind: VxButtonKind.outline, onPressed: _disable),
                ]
              : [
                  VxButton(
                    label: 'Activer',
                    icon: Icons.shield_rounded,
                    kind: VxButtonKind.secondary,
                    onPressed: _enable,
                  ),
                ],
        ),
        if (enabled)
          TextButton(
            onPressed: _forgot,
            child: Text('Code oublié ?', style: VxText.body(14 * s, weight: FontWeight.w600)),
          ),
      ],
    );
  }
}

/// « Code oublié » : the account password turns parental control off.
class ParentalPasswordDialog extends StatefulWidget {
  const ParentalPasswordDialog({super.key});

  @override
  State<ParentalPasswordDialog> createState() => _ParentalPasswordDialogState();
}

class _ParentalPasswordDialogState extends State<ParentalPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Code oublié'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Le mot de passe du compte désactive le contrôle parental ; vous pourrez ensuite définir un '
            'nouveau code.',
            style: VxText.body(15, color: VxColors.textSoft),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            onSubmitted: (_) => Navigator.pop(context, _password.text),
            decoration: const InputDecoration(labelText: 'Mot de passe du compte'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      VxButton(label: 'Continuer', onPressed: () => Navigator.pop(context, _password.text)),
    ],
  );
}

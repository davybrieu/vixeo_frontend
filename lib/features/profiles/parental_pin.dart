import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../auth/session.dart';

// Parental PIN of the account (vixeo_backend/docs/controle-parental.md): the "Code PIN" page, and
// what both it and "Contrôle parental" use (the PIN asked on arrival, PIN fields and dialogs).

/// A page that needs the parental PIN when one is set: asks it on arrival, keeps it in memory
/// while the page is open (never stored), and gives it to [builder] (null without parental
/// control) with a way to replace it (changed, removed).
class ParentalPinPage extends ConsumerStatefulWidget {
  const ParentalPinPage({super.key, required this.title, required this.builder});

  final String title;
  final Widget Function(BuildContext context, String? pin, ValueChanged<String?> onPinChanged) builder;

  @override
  ConsumerState<ParentalPinPage> createState() => _ParentalPinPageState();
}

class _ParentalPinPageState extends ConsumerState<ParentalPinPage> {
  String? _pin;

  @override
  void initState() {
    super.initState();
    // The status may have changed on another device.
    ref.read(sessionProvider.notifier).refreshUser().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final enabled = ref.watch(sessionProvider.select((s) => s.user?.parentalControl ?? false));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: VxColors.background,
        title: Text(widget.title, style: VxText.title(layout.isLarge ? layout.tv(30) : 20)),
      ),
      body: enabled && _pin == null
          ? ParentalPinGate(onUnlocked: (pin) => setState(() => _pin = pin))
          : widget.builder(context, _pin, (pin) => setState(() => _pin = pin)),
    );
  }
}

/// Asks the parental PIN before showing a page; "Code oublié ?" turns parental control off with the
/// account password.
class ParentalPinGate extends ConsumerStatefulWidget {
  const ParentalPinGate({super.key, required this.onUnlocked});

  final ValueChanged<String> onUnlocked;

  @override
  ConsumerState<ParentalPinGate> createState() => _ParentalPinGateState();
}

class _ParentalPinGateState extends ConsumerState<ParentalPinGate> {
  final _pin = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_pin.text.length != 4) {
      setState(() => _error = 'Saisissez les 4 chiffres.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyParentalPin(_pin.text);
      widget.onUnlocked(_pin.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.field('pin') ?? e.message;
          _pin.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final password = await showDialog<String>(context: context, builder: (_) => const PasswordDialog());
    if (password == null || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).disableParentalControl(password: password);
      await ref.read(sessionProvider.notifier).refreshUser();
      if (mounted) {
        showVxSnack(
          context,
          'Contrôle parental désactivé. Vous pouvez définir un nouveau code.',
          icon: Icons.lock_open_rounded,
        );
      }
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.field('password') ?? e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24 * s),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 380 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.shield_rounded, size: 48 * s, color: VxColors.accent),
              SizedBox(height: 16 * s),
              Text('Code PIN parental', style: VxText.title(22 * s), textAlign: TextAlign.center),
              SizedBox(height: 8 * s),
              Text(
                'Saisissez le code pour accéder aux réglages.',
                style: VxText.body(15 * s, color: VxColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24 * s),
              PinField(controller: _pin, error: _error, autofocus: true, onSubmitted: _check, scale: s),
              SizedBox(height: 20 * s),
              VxButton(label: 'Valider', onPressed: _check, loading: _loading, expand: true),
              SizedBox(height: 8 * s),
              TextButton(
                onPressed: _forgot,
                child: Text('Code oublié ?', style: VxText.body(14 * s, weight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Code PIN" (`/profil/code-pin`): turns the parental PIN on, changes it or turns it off. The PIN
/// is asked for creating or deleting a profile and for changing its restrictions.
class ParentalPinScreen extends StatelessWidget {
  const ParentalPinScreen({super.key});

  @override
  Widget build(BuildContext context) => ParentalPinPage(
    title: 'Code PIN',
    builder: (context, pin, onPinChanged) => _PinSettings(pin: pin, onPinChanged: onPinChanged),
  );
}

class _PinSettings extends ConsumerWidget {
  const _PinSettings({required this.pin, required this.onPinChanged});

  final String? pin;
  final ValueChanged<String?> onPinChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final enabled = ref.watch(sessionProvider.select((s) => s.user?.parentalControl ?? false));
    final auth = ref.read(authRepositoryProvider);

    Future<void> enable() async {
      final newPin = await showDialog<String>(context: context, builder: (_) => const NewPinDialog());
      if (newPin == null || !context.mounted) return;
      try {
        await auth.setParentalPin(newPin);
        await ref.read(sessionProvider.notifier).refreshUser();
        onPinChanged(newPin);
        if (context.mounted) showVxSnack(context, 'Contrôle parental activé', icon: Icons.shield_rounded);
      } on ApiException catch (e) {
        if (context.mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
      }
    }

    Future<void> change() async {
      final newPin = await showDialog<String>(context: context, builder: (_) => const NewPinDialog(changing: true));
      if (newPin == null || !context.mounted) return;
      try {
        await auth.setParentalPin(newPin, currentPin: pin);
        onPinChanged(newPin);
        if (context.mounted) showVxSnack(context, 'Code PIN parental modifié', icon: Icons.shield_rounded);
      } on ApiException catch (e) {
        if (context.mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
      }
    }

    Future<void> disable() async {
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
      if (ok != true || !context.mounted) return;
      try {
        await auth.disableParentalControl(currentPin: pin);
        await ref.read(sessionProvider.notifier).refreshUser();
        onPinChanged(null);
        if (context.mounted) showVxSnack(context, 'Contrôle parental désactivé', icon: Icons.lock_open_rounded);
      } on ApiException catch (e) {
        if (context.mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
      }
    }

    // The same column as the other secondary pages (InfoBody), with the charter's card.
    return InfoBody(
      children: [
        VxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    enabled ? Icons.shield_rounded : Icons.shield_outlined,
                    size: 24 * s,
                    color: enabled ? VxColors.accent : VxColors.textMuted,
                  ),
                  SizedBox(width: 10 * s),
                  Expanded(child: Text('Code PIN parental', style: VxText.title(18 * s))),
                  VxBadge(enabled ? 'Activé' : 'Désactivé', accent: enabled, fontSize: 12 * s),
                ],
              ),
              SizedBox(height: 10 * s),
              Text(
                enabled
                    ? 'Le code est demandé pour créer ou supprimer un profil et pour modifier ses restrictions.'
                    : 'Sans code, n’importe qui peut créer un profil ou retirer les restrictions d’un profil enfant.',
                style: VxText.body(14 * s, color: VxColors.textSecondary),
              ),
              SizedBox(height: 16 * s),
              Wrap(
                spacing: 12 * s,
                runSpacing: 12 * s,
                children: enabled
                    ? [
                        VxButton(
                          label: 'Changer le code',
                          icon: Icons.password_rounded,
                          kind: VxButtonKind.secondary,
                          autofocus: true,
                          onPressed: change,
                        ),
                        VxButton(label: 'Désactiver', kind: VxButtonKind.outline, onPressed: disable),
                      ]
                    : [
                        VxButton(
                          label: 'Activer le contrôle parental',
                          icon: Icons.shield_rounded,
                          autofocus: true,
                          onPressed: enable,
                        ),
                      ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 4 hidden digits.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    this.error,
    this.autofocus = false,
    this.onSubmitted,
    this.label,
    this.scale = 1,
  });

  final TextEditingController controller;
  final String? error;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final String? label;
  final double scale;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: 4,
    textAlign: TextAlign.center,
    style: VxText.title(28 * scale).copyWith(letterSpacing: 16 * scale),
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onSubmitted: (_) => onSubmitted?.call(),
    decoration: InputDecoration(counterText: '', hintText: '••••', labelText: label, errorText: error),
  );
}

/// New 4-digit PIN, typed twice. Pops the PIN.
class NewPinDialog extends StatefulWidget {
  const NewPinDialog({super.key, this.changing = false});

  final bool changing;

  @override
  State<NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<NewPinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pin.text.length != 4) {
      setState(() => _error = 'Le code doit contenir 4 chiffres.');
    } else if (_pin.text != _confirm.text) {
      setState(() => _error = 'Les deux codes ne sont pas identiques.');
    } else {
      Navigator.pop(context, _pin.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.changing ? 'Nouveau code PIN parental' : 'Choisissez un code PIN parental'),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PinField(controller: _pin, autofocus: true, label: 'Code'),
          const SizedBox(height: 12),
          PinField(controller: _confirm, label: 'Confirmation', error: _error, onSubmitted: _submit),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      VxButton(label: 'Enregistrer', onPressed: _submit),
    ],
  );
}

/// Account password ("code oublié"). Pops the password.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
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
            'Saisissez le mot de passe du compte pour désactiver le contrôle parental, '
            'puis choisissez un nouveau code.',
            style: VxText.body(14, color: VxColors.textSecondary),
          ),
          const SizedBox(height: 16),
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

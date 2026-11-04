import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import 'avatars.dart';
import 'profiles_screen.dart';

/// Age limits offered for a profile (null = none, or 10 for a kid profile).
const _ageOptions = <int?>[null, 0, 7, 10, 12, 16, 18];

/// Phone sizes × this factor on large screens: about the 1920 design's sizes (VxButton, section titles).
double _scaleOf(BuildContext context) {
  final layout = Layout.of(context);
  return layout.isLarge ? layout.scale * 1.6 : 1.0;
}

String _ageLabel(int? age, {required bool kid}) => switch (age) {
  null => kid ? 'Par défaut (10 ans)' : 'Aucune limite',
  0 => 'Tous publics',
  final a => '$a ans',
};

/// "Contrôle parental": parental PIN and each profile's restrictions.
/// When a parental PIN is set, it is asked once on arrival and sent with every change.
class ParentalControlScreen extends ConsumerStatefulWidget {
  const ParentalControlScreen({super.key});

  @override
  ConsumerState<ParentalControlScreen> createState() => _ParentalControlScreenState();
}

class _ParentalControlScreenState extends ConsumerState<ParentalControlScreen> {
  /// Parental PIN typed on arrival (kept only while this screen is open).
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
        title: Text('Contrôle parental', style: VxText.title(layout.isLarge ? layout.tv(30) : 20)),
      ),
      body: enabled && _pin == null
          ? _Gate(onUnlocked: (pin) => setState(() => _pin = pin))
          : _Settings(pin: _pin, enabled: enabled, onPinChanged: (pin) => setState(() => _pin = pin)),
    );
  }
}

/// Asks the parental PIN before showing the settings.
class _Gate extends ConsumerStatefulWidget {
  const _Gate({required this.onUnlocked});

  final ValueChanged<String> onUnlocked;

  @override
  ConsumerState<_Gate> createState() => _GateState();
}

class _GateState extends ConsumerState<_Gate> {
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
    final password = await showDialog<String>(context: context, builder: (_) => const _PasswordDialog());
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
    final s = _scaleOf(context);
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
              _PinField(controller: _pin, error: _error, autofocus: true, onSubmitted: _check, scale: s),
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

class _Settings extends ConsumerWidget {
  const _Settings({required this.pin, required this.enabled, required this.onPinChanged});

  final String? pin;
  final bool enabled;
  final ValueChanged<String?> onPinChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final s = _scaleOf(context);
    final profiles = ref.watch(profilesProvider);
    final auth = ref.read(authRepositoryProvider);

    Future<void> enable() async {
      final newPin = await showDialog<String>(context: context, builder: (_) => const _NewPinDialog());
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
      final newPin = await showDialog<String>(context: context, builder: (_) => const _NewPinDialog(changing: true));
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

    return ListView(
      padding: EdgeInsets.fromLTRB(layout.gutter, 8 * s, layout.gutter, 40 * s),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Card(
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
                          Text('Code PIN parental', style: VxText.title(18 * s)),
                          const Spacer(),
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
                SizedBox(height: 28 * s),
                Text('Restrictions des profils', style: VxText.title(18 * s)),
                SizedBox(height: 6 * s),
                Text(
                  'Les titres au-dessus de l’âge choisi sont masqués du catalogue et de la recherche.',
                  style: VxText.body(14 * s, color: VxColors.textSecondary),
                ),
                SizedBox(height: 14 * s),
                AsyncView(
                  value: profiles,
                  onRetry: () => ref.invalidate(profilesProvider),
                  data: (list) => Column(
                    children: [
                      for (final profile in list)
                        Padding(
                          padding: EdgeInsets.only(bottom: 14 * s),
                          child: _ProfileRestrictions(profile: profile, pin: pin),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileRestrictions extends ConsumerStatefulWidget {
  const _ProfileRestrictions({required this.profile, required this.pin});

  final Profile profile;
  final String? pin;

  @override
  ConsumerState<_ProfileRestrictions> createState() => _ProfileRestrictionsState();
}

class _ProfileRestrictionsState extends ConsumerState<_ProfileRestrictions> {
  late Profile _profile = widget.profile;
  bool _saving = false;

  @override
  void didUpdateWidget(_ProfileRestrictions old) {
    super.didUpdateWidget(old);
    if (!_saving) _profile = widget.profile;
  }

  Future<void> _save(Map<String, Object?> fields, String done) async {
    setState(() => _saving = true);
    try {
      final updated = await ref.read(authRepositoryProvider).updateProfile(_profile.id, {
        ...fields,
        'parental_pin': ?widget.pin,
      });
      if (!mounted) return;
      setState(() => _profile = updated);
      ref.read(sessionProvider.notifier).updateProfile(updated);
      ref.invalidate(profilesProvider);
      // The catalog is filtered with the active profile's limits: reload it.
      ref.invalidate(homeProvider);
      showVxSnack(context, done, icon: Icons.shield_rounded);
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.field('parental_pin') ?? e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final restricted = p.isKid || p.maxAgeRating != null;
    final s = _scaleOf(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(profile: p, size: 44 * s),
              SizedBox(width: 12 * s),
              Expanded(child: Text(p.name, style: VxText.title(18 * s))),
              if (_saving) SizedBox.square(dimension: 20 * s, child: const CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
          SizedBox(height: 8 * s),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.isKid,
            onChanged: _saving
                ? null
                : (v) => _save({'is_kid': v}, v ? '${p.name} : profil enfant' : '${p.name} : profil adulte'),
            title: Text('Profil enfant', style: VxText.body(16 * s, weight: FontWeight.w500)),
            subtitle: Text(
              'Sans âge choisi, limité aux titres pour les 10 ans et moins.',
              style: VxText.body(13 * s, color: VxColors.textSecondary),
            ),
          ),
          SizedBox(height: 6 * s),
          Text(
            'Âge maximum',
            style: VxText.body(14 * s, weight: FontWeight.w600, color: VxColors.textSoft),
          ),
          SizedBox(height: 10 * s),
          FocusTraversalGroup(
            child: Wrap(
              spacing: 8 * s,
              runSpacing: 8 * s,
              children: [
                for (final age in _ageOptions)
                  _Chip(
                    label: _ageLabel(age, kid: p.isKid),
                    selected: p.maxAgeRating == age,
                    scale: s,
                    // The selected chip stays a (no-op) button: same role for screen readers, same focus on TV.
                    onPressed: _saving
                        ? null
                        : () {
                            if (p.maxAgeRating == age) return;
                            _save({'max_age_rating': age}, '${p.name} : ${_ageLabel(age, kid: p.isKid).toLowerCase()}');
                          },
                  ),
              ],
            ),
          ),
          SizedBox(height: 6 * s),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.allowUnrated,
            onChanged: _saving || !restricted
                ? null
                : (v) => _save({
                    'allow_unrated': v,
                  }, v ? 'Titres sans classification affichés' : 'Titres sans classification masqués'),
            title: Text('Titres sans classification', style: VxText.body(16 * s, weight: FontWeight.w500)),
            subtitle: Text(
              restricted
                  ? 'Afficher aussi les titres dont l’âge conseillé est inconnu.'
                  : 'Seulement avec une limite d’âge.',
              style: VxText.body(13 * s, color: VxColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onPressed, this.scale = 1});

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final double scale;

  @override
  Widget build(BuildContext context) => VxFocusable(
    borderRadius: 18 * scale,
    semanticLabel: '$label${selected ? ', sélectionné' : ''}',
    onPressed: onPressed,
    child: Container(
      height: 36 * scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
      decoration: BoxDecoration(
        color: selected ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
        border: selected ? null : Border.all(color: VxColors.lineStrong),
        borderRadius: BorderRadius.circular(18 * scale),
      ),
      // widthFactor 1: as wide as the label (a plain `alignment` would fill the whole row).
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: VxText.body(14 * scale, weight: FontWeight.w600, color: selected ? VxColors.accent : VxColors.text),
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  // A Material (not a colored box): the switches inside draw their ink on it.
  @override
  Widget build(BuildContext context) {
    final s = _scaleOf(context);
    return Material(
      color: VxColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20 * s),
        side: const BorderSide(color: VxColors.surfaceHigh),
      ),
      child: Padding(
        padding: EdgeInsets.all(20 * s),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
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
class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog({this.changing = false});

  final bool changing;

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
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
          _PinField(controller: _pin, autofocus: true, label: 'Code'),
          const SizedBox(height: 12),
          _PinField(controller: _confirm, label: 'Confirmation', error: _error, onSubmitted: _submit),
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
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
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

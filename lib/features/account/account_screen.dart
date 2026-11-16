import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/session.dart';
import 'info_page.dart';

/// "Mon compte" (`/profil/compte`): change the e-mail address and the password, receive a copy of
/// the data, delete the account (GDPR).
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final message = await ref.read(authRepositoryProvider).exportData();
      if (mounted) showVxSnack(context, message, icon: Icons.mark_email_read_outlined);
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _changeEmail() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _EmailDialog());
    if (changed == true && mounted) showVxSnack(context, 'Adresse e-mail modifiée', icon: Icons.check_circle_rounded);
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _PasswordDialog());
    if (changed == true && mounted) {
      showVxSnack(context, 'Mot de passe modifié. Vos autres appareils ont été déconnectés.', icon: Icons.lock_rounded);
    }
  }

  Future<void> _delete() async {
    final deleted = await showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
    if (deleted != true) return;
    // The router goes back to the sign-in page, which shows this message.
    await ref.read(sessionProvider.notifier).forget(message: 'Votre compte et toutes ses données ont été supprimés.');
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return InfoPage(
      title: 'Mon compte',
      fallback: '/profil',
      children: [
        InfoSection(
          title: 'Adresse e-mail',
          children: [
            const InfoText('Changez l’adresse e-mail de votre compte, celle qui sert à vous connecter.'),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(
              label: 'Modifier l’adresse e-mail',
              icon: Icons.alternate_email_rounded,
              kind: VxButtonKind.secondary,
              autofocus: true,
              onPressed: _changeEmail,
            ),
          ],
        ),
        InfoSection(
          title: 'Mot de passe',
          children: [
            const InfoText('Changer le mot de passe déconnecte vos autres appareils ; celui-ci reste connecté.'),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(
              label: 'Changer le mot de passe',
              icon: Icons.lock_reset_rounded,
              kind: VxButtonKind.secondary,
              onPressed: _changePassword,
            ),
          ],
        ),
        InfoSection(
          title: 'Vos données',
          children: [
            const InfoText(
              'Recevez par e-mail un fichier avec tout ce que Vixeo conserve sur votre compte : profils, liste, '
              'progression et appareils connectés.',
            ),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(
              label: 'Recevoir mes données',
              icon: Icons.download_rounded,
              kind: VxButtonKind.secondary,
              loading: _exporting,
              onPressed: _export,
            ),
          ],
        ),
        InfoSection(
          title: 'Supprimer le compte',
          last: true,
          children: [
            const InfoText(
              'Le compte, tous ses profils, leur liste et leur progression sont effacés définitivement, et tous '
              'les appareils sont déconnectés. Il n’est pas possible de revenir en arrière.',
            ),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(
              label: 'Supprimer mon compte',
              icon: Icons.delete_forever_outlined,
              kind: VxButtonKind.danger,
              onPressed: _delete,
            ),
          ],
        ),
      ],
    );
  }
}

/// Asks the account password, then deletes the account. Pops true once deleted.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Saisissez le mot de passe du compte.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).deleteAccount(_password.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.field('password') ?? e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Supprimer le compte ?'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tous les profils, leur liste et leur progression seront effacés définitivement. '
            'Saisissez le mot de passe du compte pour confirmer.',
            style: VxText.body(14, color: VxColors.textSecondary),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: 'Mot de passe',
            error: _error,
            autofocus: true,
            onSubmitted: _confirm,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _loading ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
      VxButton(label: 'Supprimer définitivement', loading: _loading, onPressed: _confirm),
    ],
  );
}

/// A password field with the eye button that shows it in clear (« Afficher le mot de passe »).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.autofocus = false,
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final bool autofocus;

  /// A password being chosen (the system offers to save it), not one being typed to confirm.
  final bool newPassword;
  final VoidCallback? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: !_shown,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
    textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
    onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.error,
      suffixIcon: IconButton(
        tooltip: _shown ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
        icon: Icon(_shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        color: VxColors.textSecondary,
        onPressed: () => setState(() => _shown = !_shown),
      ),
    ),
  );
}

/// The new e-mail address and the account password. Pops true once changed (the session keeps
/// the new address).
class _EmailDialog extends ConsumerStatefulWidget {
  const _EmailDialog();

  @override
  ConsumerState<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends ConsumerState<_EmailDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final email = _email.text.trim();
    setState(() {
      _emailError = email.contains('@') ? null : 'Adresse e-mail invalide.';
      _passwordError = _password.text.isEmpty ? 'Saisissez le mot de passe du compte.' : null;
    });
    if (_emailError != null || _passwordError != null) return;
    setState(() => _loading = true);
    try {
      final user = await ref.read(authRepositoryProvider).updateEmail(email: email, password: _password.text);
      ref.read(sessionProvider.notifier).updateUser(user);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _emailError = e.field('email');
          _passwordError = e.field('password') ?? (e.field('email') == null ? e.message : null);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Modifier l’adresse e-mail'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Elle sert à vous connecter et à recevoir les codes « mot de passe oublié ».',
            style: VxText.body(14, color: VxColors.textSecondary),
          ),
          const SizedBox(height: 16),
          // The address in use, to read only.
          TextFormField(
            initialValue: ref.watch(sessionProvider.select((s) => s.user?.email)) ?? '',
            readOnly: true,
            enableInteractiveSelection: true,
            style: VxText.body(16, color: VxColors.textSecondary),
            decoration: const InputDecoration(labelText: 'Adresse e-mail actuelle'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: 'Nouvelle adresse e-mail', errorText: _emailError),
          ),
          const SizedBox(height: 16),
          PasswordField(controller: _password, label: 'Mot de passe', error: _passwordError, onSubmitted: _confirm),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _loading ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
      VxButton(label: 'Enregistrer', loading: _loading, onPressed: _confirm),
    ],
  );
}

/// The current password and the new one. Pops true once changed.
class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  String? _currentError;
  String? _passwordError;
  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _currentError = _current.text.isEmpty ? 'Saisissez votre mot de passe actuel.' : null;
      _passwordError = _password.text.isEmpty ? 'Saisissez le nouveau mot de passe.' : null;
    });
    if (_currentError != null || _passwordError != null) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(current: _current.text, password: _password.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _currentError = e.field('current_password');
          _passwordError = e.field('password') ?? (e.field('current_password') == null ? e.message : null);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Changer le mot de passe'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PasswordField(controller: _current, label: 'Mot de passe actuel', error: _currentError, autofocus: true),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: 'Nouveau mot de passe',
            error: _passwordError,
            newPassword: true,
            onSubmitted: _confirm,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _loading ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
      VxButton(label: 'Enregistrer', loading: _loading, onPressed: _confirm),
    ],
  );
}

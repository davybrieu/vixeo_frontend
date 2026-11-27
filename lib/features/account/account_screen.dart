import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/session.dart';
import '../auth/email_sign_in.dart';
import 'info_page.dart';

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
    if (changed == true && mounted) showVxSnack(context, 'Votre nouvelle adresse e-mail a été confirmée.');
  }

  Future<void> _delete() async {
    final deleted = await showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
    if (deleted == true) {
      await ref.read(sessionProvider.notifier).forget(message: 'Votre compte et toutes ses données ont été supprimés.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final user = ref.watch(sessionProvider.select((s) => s.user));
    return InfoPage(
      title: 'Mon compte',
      fallback: '/profil',
      children: [
        InfoSection(
          title: 'Adresse e-mail',
          children: [
            InfoText('Votre adresse e-mail sert à vous connecter. À chaque connexion, Vixeo vous envoie un lien à usage unique.'),
            SizedBox(height: layout.space(VxSpace.xs)),
            InfoText(user?.email ?? ''),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(label: 'Modifier l’adresse e-mail', icon: Icons.alternate_email_rounded, kind: VxButtonKind.secondary, autofocus: true, onPressed: _changeEmail),
          ],
        ),
        InfoSection(
          title: 'Vos données',
          children: [
            const InfoText('Recevez par e-mail un fichier avec tout ce que Vixeo conserve sur votre compte : profil, liste, progression et appareils connectés.'),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(label: 'Recevoir mes données', icon: Icons.download_rounded, kind: VxButtonKind.secondary, loading: _exporting, onPressed: _export),
          ],
        ),
        InfoSection(
          title: 'Supprimer le compte',
          last: true,
          children: [
            const InfoText('Le compte, son profil, sa liste et sa progression seront effacés définitivement. Tous les appareils seront déconnectés.'),
            SizedBox(height: layout.space(VxSpace.xs)),
            VxButton(label: 'Supprimer mon compte', icon: Icons.delete_forever_outlined, kind: VxButtonKind.danger, onPressed: _delete),
          ],
        ),
      ],
    );
  }
}

class _EmailDialog extends ConsumerStatefulWidget {
  const _EmailDialog();
  @override
  ConsumerState<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends ConsumerState<_EmailDialog> {
  final _email = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() { _email.dispose(); super.dispose(); }

  Future<void> _confirm() async {
    final email = _email.text.trim();
    if (!email.contains('@')) { setState(() => _error = 'Adresse e-mail invalide.'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final result = await changeEmailWithLink(ref, email: email);
      if (result != null) {
        await ref.read(sessionProvider.notifier).signInWithToken(result.token, result.user);
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.field('email') ?? e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle adresse e-mail'),
    content: SizedBox(width: 380, child: TextField(
      controller: _email, autofocus: true, keyboardType: TextInputType.emailAddress, autocorrect: false,
      decoration: InputDecoration(labelText: 'Adresse e-mail', errorText: _error),
      onSubmitted: (_) => _confirm(),
    )),
    actions: [
      TextButton(onPressed: _loading ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
      VxButton(label: 'Enregistrer', loading: _loading, onPressed: _confirm),
    ],
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();
  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _loading = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Supprimer le compte ?'),
    content: SizedBox(width: 380, child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tous les profils, la liste et la progression seront effacés définitivement. Cette action est irréversible.'),
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: VxText.body(14, color: VxColors.error))],
      ],
    )),
    actions: [
      TextButton(onPressed: _loading ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
      VxButton(label: 'Supprimer définitivement', kind: VxButtonKind.danger, loading: _loading, onPressed: _confirm),
    ],
  );
}

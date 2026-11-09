import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/session.dart';
import 'info_page.dart';

/// "Mon compte" (`/profil/compte`): receive a copy of the data, delete the account (GDPR).
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
              autofocus: true,
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
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(labelText: 'Mot de passe', errorText: _error),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'session.dart';

/// "Mot de passe oublié" (`/mot-de-passe-oublie`): the API e-mails a 6-digit code, typed here
/// with the new password (vixeo_backend/docs/compte.md). No link to click: the same on phones,
/// TVs and the web.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail});

  /// Address already typed on the sign-in page.
  final String? initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  bool _codeSent = false;
  bool _showPassword = false;
  bool _loading = false;
  ApiException? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    // "Renvoyer un code" (second step): the address was already checked.
    if (!_codeSent && !_emailForm.currentState!.validate()) return;
    await _run(() async {
      final message = await ref.read(authRepositoryProvider).forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
      showVxSnack(context, message, icon: Icons.mark_email_read_outlined);
    });
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    await _run(() async {
      final result = await ref
          .read(authRepositoryProvider)
          .resetPassword(email: _email.text.trim(), code: _code.text, password: _password.text);
      if (!mounted) return;
      showVxSnack(context, 'Mot de passe modifié. Les autres appareils ont été déconnectés.', icon: Icons.lock_reset);
      // Signed in: the router goes on to "Qui regarde ?".
      await ref.read(sessionProvider.notifier).signInWithToken(result.token, result.user);
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final generalError = error != null && error.fieldErrors.isEmpty ? error.message : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Retour à la connexion',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/connexion'),
        ),
        title: const VxLogo(size: 20),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _codeSent ? _resetStep(generalError) : _emailStep(generalError),
          ),
        ),
      ),
    );
  }

  Widget _emailStep(String? generalError) => Form(
    key: _emailForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mot de passe oublié', style: VxText.title(28)),
        const SizedBox(height: 8),
        Text(
          'Saisissez l’adresse de votre compte : nous vous enverrons un code pour choisir un nouveau mot de passe.',
          style: VxText.body(15, color: VxColors.textSecondary),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          onFieldSubmitted: (_) => _sendCode(),
          decoration: InputDecoration(labelText: 'Adresse e-mail', errorText: _error?.field('email')),
          validator: (v) => (v ?? '').trim().contains('@') ? null : 'Adresse e-mail invalide.',
        ),
        const SizedBox(height: 24),
        if (generalError != null) ...[
          Text(generalError, style: VxText.body(14, color: VxColors.error)),
          const SizedBox(height: 12),
        ],
        VxButton(label: 'Recevoir un code', onPressed: _sendCode, loading: _loading, expand: true),
      ],
    ),
  );

  Widget _resetStep(String? generalError) => Form(
    key: _resetForm,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nouveau mot de passe', style: VxText.title(28)),
          const SizedBox(height: 8),
          Text(
            'Saisissez le code à 6 chiffres envoyé à ${_email.text.trim()}. Il est valable 15 minutes.',
            style: VxText.body(15, color: VxColors.textSecondary),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            textAlign: TextAlign.center,
            style: VxText.title(26, weight: FontWeight.w800).copyWith(letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Code reçu par e-mail',
              counterText: '',
              errorText: _error?.field('code'),
            ),
            validator: (v) => (v ?? '').length == 6 ? null : 'Le code contient 6 chiffres.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe',
              helperText: '8 caractères minimum',
              helperStyle: VxText.body(13, color: VxColors.textMuted),
              errorText: _error?.field('password'),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                color: VxColors.textSecondary,
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) => (v ?? '').length < 8 ? 'Au moins 8 caractères.' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _reset(),
            decoration: const InputDecoration(labelText: 'Confirmation du mot de passe'),
            validator: (v) => v == _password.text ? null : 'Les deux mots de passe ne sont pas identiques.',
          ),
          const SizedBox(height: 24),
          if (generalError != null) ...[
            Text(generalError, style: VxText.body(14, color: VxColors.error)),
            const SizedBox(height: 12),
          ],
          VxButton(label: 'Changer le mot de passe', onPressed: _reset, loading: _loading, expand: true),
          const SizedBox(height: 12),
          TextButton(onPressed: _loading ? null : _sendCode, child: const Text('Renvoyer un code')),
        ],
      ),
    ),
  );
}

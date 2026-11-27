import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import 'device_login.dart';
import 'session.dart';
import 'social_sign_in.dart';

/// Entry page of the app (`/connexion`), like the other film apps' (developer's request,
/// 25/11/2026): the logo, a tagline, then « Continuer avec Google », « Continuer avec Apple » and
/// Connexion par code à usage unique envoyé par e-mail.
class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});
  static const location = '/connexion/email';
  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}
class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  ApiException? _error;

  @override
  void dispose() { _email.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (!_codeSent) {
        await repository.requestEmailCode(email: _email.text.trim());
        if (mounted) setState(() => _codeSent = true);
      } else {
        final result = await repository.verifyEmailCode(email: _email.text.trim(), code: _code.text.trim());
        await ref.read(sessionProvider.notifier).signInWithToken(result.token, result.user);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (_) {
      if (mounted) setState(() => _error = ApiException(
        _codeSent ? 'Impossible de vérifier le code.' : 'Impossible d’envoyer le code de connexion.',
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).requestEmailCode(email: _email.text.trim());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeEmail() {
    setState(() { _codeSent = false; _code.clear(); _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/connexion'),
        ),
        title: const VxLogo(size: 20),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.isLarge ? layout.tv(640).clamp(440, 640).toDouble() : 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_codeSent ? 'Saisissez votre code' : 'Se connecter avec l’e-mail',
                    style: VxText.title(layout.isLarge ? 32 : 28)),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent
                        ? 'Un code à 6 chiffres a été envoyé à ${_email.text.trim()}. Il est valable 10 minutes.'
                        : 'Saisissez votre adresse e-mail. Nous vous enverrons un code à 6 chiffres valable 10 minutes.',
                    style: VxText.body(15, color: VxColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    readOnly: _codeSent,
                    autofocus: !_codeSent,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    textInputAction: _codeSent ? TextInputAction.next : TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(labelText: 'Adresse e-mail', errorText: _error?.field('email')),
                    validator: (v) => (v ?? '').trim().contains('@') ? null : 'Adresse e-mail invalide.',
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: VxText.title(28).copyWith(letterSpacing: 10),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(labelText: 'Code de vérification', counterText: '', errorText: _error?.field('code')),
                      validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
                          ? null : 'Saisissez les 6 chiffres reçus par e-mail.',
                    ),
                  ],
                  if (_error != null && _error!.fieldErrors.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_error!.message, style: VxText.body(14, color: VxColors.error)),
                  ],
                  const SizedBox(height: 24),
                  VxButton(
                    label: _codeSent ? 'Valider et me connecter' : 'Recevoir mon code',
                    onPressed: _submit, loading: _loading, expand: true,
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 12),
                    TextButton(onPressed: _loading ? null : _resendCode, child: const Text('Renvoyer un code')),
                    TextButton(onPressed: _loading ? null : _changeEmail, child: const Text('Modifier mon adresse e-mail')),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Première connexion ? Votre compte sera créé automatiquement après validation du code. Vous pourrez ensuite compléter votre profil.',
                    textAlign: TextAlign.center,
                    style: VxText.body(13, color: VxColors.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

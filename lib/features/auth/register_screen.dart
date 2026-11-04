import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'session.dart';

/// Account creation (also creates the first profile, named after the user).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).register(_name.text.trim(), _email.text.trim(), _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Créer un compte', style: VxText.title(28)),
                    const SizedBox(height: 8),
                    Text(
                      'Un compte pour toute la famille : chacun aura ensuite son profil.',
                      style: VxText.body(15, color: VxColors.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _name,
                      autofillHints: const [AutofillHints.givenName],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: 'Prénom', errorText: error?.field('name')),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Saisissez votre prénom.' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(labelText: 'Adresse e-mail', errorText: error?.field('email')),
                      validator: (v) => (v ?? '').contains('@') ? null : 'Adresse e-mail invalide.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        helperText: '8 caractères minimum',
                        helperStyle: VxText.body(13, color: VxColors.textMuted),
                        errorText: error?.field('password'),
                      ),
                      validator: (v) => (v ?? '').length < 8 ? 'Au moins 8 caractères.' : null,
                    ),
                    const SizedBox(height: 24),
                    if (generalError != null) ...[
                      Text(generalError, style: VxText.body(14, color: VxColors.error)),
                      const SizedBox(height: 12),
                    ],
                    VxButton(label: 'Créer mon compte', onPressed: _submit, loading: _loading, expand: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

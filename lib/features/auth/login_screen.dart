import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'device_login.dart';
import 'session.dart';

/// Main page of the app: sign in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    // "Session expirée" and similar messages from the session.
    final message = ref.read(sessionProvider).message;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showVxSnack(context, message);
      });
    }
  }

  @override
  void dispose() {
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
      await ref.read(sessionProvider.notifier).login(_email.text.trim(), _password.text);
      // The router moves on to "Qui regarde ?".
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    // Large screens: QR card and form side by side when they fit (a 1080p TV is ~960 dp wide).
    final available = layout.width - 2 * layout.gutter - 64;
    final formWidth = (available * 0.45).clamp(360.0, 480.0);
    final qrWidth = (available - formWidth - 40).clamp(400.0, 640.0);
    final form = _LoginForm(
      formKey: _formKey,
      email: _email,
      password: _password,
      showPassword: _showPassword,
      onTogglePassword: () => setState(() => _showPassword = !_showPassword),
      loading: _loading,
      error: _error,
      onSubmit: _submit,
      large: !layout.isPhone,
    );

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: PosterWall()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: layout.isPhone
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x4D070A08), Color(0xCC070A08), VxColors.background],
                        stops: [0, 0.35, 0.6],
                      )
                    : null,
                color: layout.isPhone ? null : const Color(0xD6070A08),
              ),
            ),
          ),
          SafeArea(
            child: layout.isPhone
                ? LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight - 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 12), child: VxLogo(size: 34)),
                            const SizedBox(height: 120),
                            form,
                          ],
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          VxLogo(size: layout.isLarge ? layout.tv(52).clamp(30, 60).toDouble() : 40),
                          const SizedBox(height: 32),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 40,
                            runSpacing: 32,
                            children: [
                              // TV / large screen: sign in from a phone with a QR code.
                              if (layout.isLarge) SizedBox(width: qrWidth, child: const TvCodeCard()),
                              Container(
                                width: formWidth,
                                padding: const EdgeInsets.all(36),
                                decoration: BoxDecoration(
                                  color: VxColors.surface.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: VxColors.line),
                                ),
                                child: form,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.email,
    required this.password,
    required this.showPassword,
    required this.onTogglePassword,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.large,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool showPassword;
  final VoidCallback onTogglePassword;
  final bool loading;
  final ApiException? error;
  final VoidCallback onSubmit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final emailError = error?.field('email');
    final generalError = error != null && emailError == null && error!.field('password') == null
        ? error!.message
        : null;

    return Form(
      key: formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(large ? 'Connectez-vous' : 'Vos films et séries, sur tous vos écrans.', style: VxText.title(28)),
            const SizedBox(height: 8),
            Text(
              'Connectez-vous pour retrouver vos profils, vos favoris et votre progression.',
              style: VxText.body(15, color: VxColors.textSecondary),
            ),
            const SizedBox(height: 24),
            _FieldLabel('Adresse e-mail'),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              style: VxText.body(16),
              decoration: InputDecoration(hintText: 'vous@exemple.fr', errorText: emailError),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Saisissez votre adresse e-mail.';
                if (!v.contains('@') || !v.contains('.')) return 'Adresse e-mail invalide.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _FieldLabel('Mot de passe'),
            TextFormField(
              controller: password,
              obscureText: !showPassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => onSubmit(),
              style: VxText.body(16),
              decoration: InputDecoration(
                hintText: 'Votre mot de passe',
                errorText: error?.field('password'),
                suffixIcon: IconButton(
                  tooltip: showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
                  icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  color: VxColors.textSecondary,
                  onPressed: onTogglePassword,
                ),
              ),
              validator: (value) => (value ?? '').isEmpty ? 'Saisissez votre mot de passe.' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/mot-de-passe-oublie', extra: email.text.trim()),
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
            if (generalError != null) ...[
              Text(generalError, style: VxText.body(14, color: VxColors.error)),
              const SizedBox(height: 12),
            ],
            VxButton(label: 'Se connecter', onPressed: onSubmit, loading: loading, expand: true),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Pas encore de compte ?', style: VxText.body(14, color: VxColors.textSecondary)),
                TextButton(onPressed: () => context.go('/inscription'), child: const Text('Créer un compte')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: VxText.body(14, weight: FontWeight.w500, color: VxColors.textSecondary),
    ),
  );
}

/// Decorative wall of tilted poster tiles behind the sign-in form.
class PosterWall extends StatelessWidget {
  const PosterWall({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        alignment: Alignment.topCenter,
        child: Transform.rotate(
          angle: -0.15,
          child: SizedBox(
            width: 2400,
            height: 1600,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < 160; i++)
                  Container(
                    width: 108,
                    height: 162,
                    decoration: BoxDecoration(
                      color: VxColors.tone(i * 3 + i ~/ 20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

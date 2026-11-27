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
/// « Continuer avec l’e-mail ». Google and Apple sign in in a browser (social_sign_in.dart); not on
/// a TV, which signs in with a code ([TvCodeCard], also on a large screen).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// The provider whose sign-in is under way.
  SocialProvider? _pending;

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

  Future<void> _signIn(SocialProvider provider) async {
    if (_pending != null) return;
    final messenger = ScaffoldMessenger.of(context);
    // The server has no settings for it: said at once, without opening the browser.
    if (ref.read(socialProvidersProvider).value?[provider] == false) {
      showVxSnackOn(messenger, socialSignInError(provider, 'unavailable')!);
      return;
    }
    setState(() => _pending = provider);
    try {
      final result = await signInWith(ref, provider);
      // Signed in: the router moves on, the message (if any) stays on the next page.
      if (result.message != null) showVxSnackOn(messenger, result.message!);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  void _cancel() {
    ref.read(browserAuthorizerProvider)?.cancel();
    setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final social = ref.watch(browserAuthorizerProvider) != null;
    // Known before a tap: a provider the server isn't set up for says so without the browser.
    if (social) ref.watch(socialProvidersProvider);

    final buttons = _WelcomeButtons(
      social: social,
      pending: _pending,
      onSocial: _signIn,
      onEmail: () => context.go(EmailLoginScreen.location),
      onCancel: _cancel,
    );
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _WelcomeBackground()),
          SafeArea(
            child: layout.isPhone
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        // The logo at the top, the tagline in the middle, the buttons at the bottom.
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              children: [
                                const VxLogo(size: 40),
                              ],
                            ),
                            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: _Tagline()),
                            Padding(padding: const EdgeInsets.only(bottom: 24), child: buttons),
                          ],
                        ),
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 40),
                          child: Column(
                            children: [
                              VxLogo(size: layout.isLarge ? layout.tv(60).clamp(34, 64).toDouble() : 44),
                              SizedBox(height: layout.isLarge ? layout.tv(56) : 40),
                              const _Tagline(),
                              SizedBox(height: layout.isLarge ? layout.tv(64) : 48),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 48,
                                runSpacing: 40,
                                children: [
                                  // TV / large screen: sign in from a phone by typing the code.
                                  if (layout.isLarge)
                                    SizedBox(width: layout.tv(620).clamp(400, 640).toDouble(), child: const TvCodeCard()),
                                  SizedBox(
                                    width: layout.isLarge ? layout.tv(560).clamp(360, 560).toDouble() : 420,
                                    child: buttons,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Two lines in the middle of the page.
class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Text(
      'Regardez vos films et vos séries\nPartagez vos avis avec la communauté',
      textAlign: TextAlign.center,
      style: VxText.title(layout.isLarge ? layout.tv(54) : 30).copyWith(height: 1.25),
    );
  }
}

/// « Continuer avec Google », « … Apple » (where a browser can sign in), « … l’e-mail ».
class _WelcomeButtons extends StatelessWidget {
  const _WelcomeButtons({
    required this.social,
    required this.pending,
    required this.onSocial,
    required this.onEmail,
    required this.onCancel,
  });

  final bool social;
  final SocialProvider? pending;
  final void Function(SocialProvider provider) onSocial;
  final VoidCallback onEmail;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final gap = layout.isLarge ? layout.tv(20) : 14.0;
    final busy = pending != null;
    return FocusTraversalGroup(
      policy: vxTraversalPolicy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (social) ...[
            _WelcomeButton(
              label: 'Continuer avec Google',
              logo: 'assets/images/sign_in/google.png',
              light: true,
              autofocus: true,
              loading: pending == SocialProvider.google,
              onPressed: busy ? null : () => onSocial(SocialProvider.google),
            ),
            SizedBox(height: gap),
            _WelcomeButton(
              label: 'Continuer avec Apple',
              logo: 'assets/images/sign_in/apple.png',
              loading: pending == SocialProvider.apple,
              onPressed: busy ? null : () => onSocial(SocialProvider.apple),
            ),
            SizedBox(height: gap),
          ],
          _WelcomeButton(
            label: 'Continuer avec l’e-mail',
            autofocus: !social,
            onPressed: busy ? null : onEmail,
          ),
          if (busy) ...[
            SizedBox(height: gap),
            Center(child: _TextLink(label: 'Annuler', onPressed: onCancel)),
          ] else if (social) ...[
            SizedBox(height: layout.isLarge ? layout.tv(28) : 20),
            Text(
              'Vixeo ne reçoit de Google ou d’Apple que votre nom et votre adresse e-mail.',
              textAlign: TextAlign.center,
              style: VxText.body(layout.isLarge ? layout.tv(20) : 13, color: VxColors.textMuted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

/// A big round-ended button of the welcome page: white (Google) or dark, with a logo.
class _WelcomeButton extends StatelessWidget {
  const _WelcomeButton({
    required this.label,
    required this.onPressed,
    this.logo,
    this.light = false,
    this.loading = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? logo;
  final bool light;
  final bool loading;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final height = layout.isLarge ? layout.tv(84) : 56.0;
    final fontSize = layout.isLarge ? layout.tv(26) : 17.0;
    final foreground = light ? const Color(0xFF1F1F1F) : VxColors.text;
    return VxFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      borderRadius: height / 2,
      focusScale: 1.03,
      semanticLabel: label,
      child: Opacity(
        opacity: onPressed == null && !loading ? 0.5 : 1,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height * 0.4),
          decoration: BoxDecoration(
            color: light ? Colors.white : VxColors.text.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox.square(
                  dimension: fontSize * 1.2,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: foreground),
                )
              else if (logo != null)
                Image.asset(logo!, width: fontSize * 1.3, height: fontSize * 1.3, excludeFromSemantics: true),
              if (loading || logo != null) SizedBox(width: fontSize * 0.75),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(fontSize, weight: FontWeight.w600, color: foreground, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small text link (« Annuler »), focusable on TV.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return VxFocusable(
      onPressed: onPressed,
      borderRadius: 10,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: VxText.body(layout.isLarge ? layout.tv(22) : 14, weight: FontWeight.w600, color: VxColors.textSecondary),
        ),
      ),
    );
  }
}

/// Dark welcome background, lit with green from the top.
class _WelcomeBackground extends StatelessWidget {
  const _WelcomeBackground();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: VxColors.background),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.7, -1.2),
              radius: 1.3,
              colors: [VxColors.accent.withValues(alpha: 0.2), VxColors.accent.withValues(alpha: 0)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.1, 0.2),
              radius: 1.1,
              colors: [VxColors.accent.withValues(alpha: 0.06), VxColors.accent.withValues(alpha: 0)],
            ),
          ),
        ),
      ],
    ),
  );
}

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
      if (mounted) _code.clear();
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
                        ? 'Un code à 6 chiffres a été envoyé à ' + _email.text.trim() + '. Il est valable 10 minutes.'
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

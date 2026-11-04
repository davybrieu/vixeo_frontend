import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'auth_repository.dart';
import 'session.dart';

/// TV sign-in card: QR code + short code, polls the API until a phone approves it.
/// A new code is fetched automatically when the current one expires.
class TvCodeCard extends ConsumerStatefulWidget {
  const TvCodeCard({super.key});

  @override
  ConsumerState<TvCodeCard> createState() => _TvCodeCardState();
}

class _TvCodeCardState extends ConsumerState<TvCodeCard> {
  DeviceCode? _code;
  Object? _error;
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    setState(() => _error = null);
    try {
      final code = await ref.read(authRepositoryProvider).startDeviceLogin();
      if (!mounted) return;
      setState(() => _code = code);
      _poll = Timer.periodic(code.interval, (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _check() async {
    final code = _code;
    if (code == null || _busy) return;
    _busy = true;
    try {
      final result = await ref.read(authRepositoryProvider).pollDeviceLogin(code.deviceCode);
      if (result != null) {
        _poll?.cancel();
        await ref.read(sessionProvider.notifier).signInWithToken(result.token, result.user);
      }
    } on ApiException catch (e) {
      // 410: expired or already used → a fresh code. Network hiccups: try again next tick.
      if (e.status == 410 && mounted) await _start();
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Sizes follow the card's own width (designed at 640): readable on a 960 dp TV as on a monitor.
    builder: (context, constraints) => _card((constraints.maxWidth / 640).clamp(0.75, 1.3).toDouble()),
  );

  Widget _card(double k) {
    final code = _code;

    Widget body;
    if (_error != null) {
      body = ErrorPanel(error: _error!, onRetry: _start);
    } else if (code == null) {
      body = SizedBox(
        height: 200 * k,
        child: const Center(child: CircularProgressIndicator()),
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            image: true,
            label: 'QR code à scanner avec votre téléphone',
            child: Container(
              padding: EdgeInsets.all(10 * k),
              decoration: BoxDecoration(color: VxColors.text, borderRadius: BorderRadius.circular(14 * k)),
              child: QrImageView(
                data: code.verificationUrlComplete,
                size: 200 * k,
                padding: EdgeInsets.zero,
                backgroundColor: VxColors.text,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: VxColors.background),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: VxColors.background,
                ),
              ),
            ),
          ),
          SizedBox(width: 28 * k),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Scannez le code, ou ouvrez ${_shortUrl(code.verificationUrl)}',
                  style: VxText.body(18 * k, color: VxColors.textSoft),
                ),
                SizedBox(height: 10 * k),
                Text('2. Saisissez ce code :', style: VxText.body(18 * k, color: VxColors.textSoft)),
                SizedBox(height: 10 * k),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    code.userCode,
                    style: VxText.title(
                      44 * k,
                      weight: FontWeight.w800,
                      color: VxColors.accent,
                    ).copyWith(letterSpacing: 4 * k),
                  ),
                ),
                SizedBox(height: 12 * k),
                Text(
                  'Un nouveau code s\u2019affiche toutes les ${code.expiresIn.inMinutes} minutes.',
                  style: VxText.body(14 * k, color: VxColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.all(32 * k),
      decoration: BoxDecoration(
        color: VxColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: VxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          VxBadge('Le plus simple', accent: true, fontSize: 14 * k),
          SizedBox(height: 14 * k),
          Text('Avec votre téléphone', style: VxText.title(30 * k)),
          SizedBox(height: 22 * k),
          body,
        ],
      ),
    );
  }

  static String _shortUrl(String url) => url.replaceFirst(RegExp(r'^https?://'), '');
}

/// Page opened by the QR code (`/tv?code=K7F29Q`): a signed-in person signs the TV in.
class DeviceApproveScreen extends ConsumerStatefulWidget {
  const DeviceApproveScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<DeviceApproveScreen> createState() => _DeviceApproveScreenState();
}

enum _Step { enterCode, confirm, done }

class _DeviceApproveScreenState extends ConsumerState<DeviceApproveScreen> {
  late final _code = TextEditingController(text: _format(widget.initialCode ?? ''));
  _Step _step = _Step.enterCode;
  String? _deviceName;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initialCode ?? '').length >= 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _code.dispose();
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
      if (mounted) setState(() => _error = e.field('user_code') ?? e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _lookup() => _run(() async {
    final name = await ref.read(authRepositoryProvider).lookupDeviceLogin(_code.text);
    if (mounted) {
      setState(() {
        _deviceName = name;
        _step = _Step.confirm;
      });
    }
  });

  Future<void> _approve() => _run(() async {
    await ref.read(authRepositoryProvider).approveDeviceLogin(_code.text);
    if (mounted) setState(() => _step = _Step.done);
  });

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: VxColors.background,
        title: Text('Connecter une TV', style: VxText.title(20)),
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: switch (_step) {
              _Step.enterCode => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.tv_rounded, size: 48, color: VxColors.accent),
                  const SizedBox(height: 16),
                  Text('Saisissez le code affiché sur la TV', style: VxText.title(22), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    style: VxText.title(30, weight: FontWeight.w800).copyWith(letterSpacing: 6),
                    inputFormatters: [_CodeFormatter()],
                    onSubmitted: (_) => _lookup(),
                    decoration: InputDecoration(hintText: 'ABC-123', errorText: _error),
                  ),
                  const SizedBox(height: 20),
                  VxButton(label: 'Continuer', onPressed: _lookup, loading: _loading, expand: true),
                ],
              ),
              _Step.confirm => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.tv_rounded, size: 48, color: VxColors.accent),
                  const SizedBox(height: 16),
                  Text(
                    '« ${_deviceName ?? 'Appareil'} » demande à se connecter',
                    style: VxText.title(22),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Il aura accès au compte ${account?.email ?? ''} et à tous ses profils. '
                    'N’autorisez que vos propres appareils.',
                    style: VxText.body(15, color: VxColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: VxText.body(14, color: VxColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  VxButton(label: 'Autoriser', onPressed: _approve, loading: _loading, expand: true, autofocus: true),
                  const SizedBox(height: 10),
                  VxButton(
                    label: 'Annuler',
                    kind: VxButtonKind.outline,
                    expand: true,
                    onPressed: () => setState(() => _step = _Step.enterCode),
                  ),
                ],
              ),
              _Step.done => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 56, color: VxColors.accent),
                  const SizedBox(height: 16),
                  Text('C’est fait !', style: VxText.title(26), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'La TV est connectée à votre compte. Elle affiche maintenant « Qui regarde ? ».',
                    style: VxText.body(15, color: VxColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  VxButton(label: 'Terminé', expand: true, autofocus: true, onPressed: () => context.go('/accueil')),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }

  static String _format(String raw) {
    final clean = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return clean.length > 3 ? '${clean.substring(0, 3)}-${clean.substring(3, clean.length.clamp(3, 6))}' : clean;
  }
}

/// Upper case, "ABC-123" shape, 6 characters max.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = _DeviceApproveScreenState._format(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

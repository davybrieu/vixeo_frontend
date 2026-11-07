import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal.dart';
import '../auth/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import 'apk_installer.dart';
import 'updates.dart';

/// Opens the install page of the site (no Play Store), when the app can't install the update
/// itself. Android TVs often have no browser: the page address is then shown instead.
Future<bool> openUpdatePage(BuildContext context, UpdateInfo info) async {
  final url = info.updateUrl;
  final uri = url == null ? null : Uri.tryParse(url);
  final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened && context.mounted) {
    final where = url == null ? 'depuis le site de Vixeo' : 'depuis ${url.replaceFirst(RegExp(r'^https?://'), '')}';
    showVxSnack(context, 'Installez la nouvelle version $where.', icon: Icons.system_update_rounded);
  }
  return opened;
}

/// "Mettre à jour": on Android, downloads and installs the APK in place (progress shown here);
/// otherwise opens the install page. Used by the dialog, the blocking screen and "À propos".
class UpdateButton extends ConsumerStatefulWidget {
  const UpdateButton({super.key, required this.info, this.autofocus = false, this.expand = false});

  final UpdateInfo info;
  final bool autofocus;
  final bool expand;

  @override
  ConsumerState<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends ConsumerState<UpdateButton> {
  bool _busy = false;
  double? _progress;
  ApkInstallResult? _result;

  Future<void> _update() async {
    final installer = ref.read(apkInstallerProvider);
    final release = widget.info.latest;
    if (!installer.canInstall(release)) {
      await openUpdatePage(context, widget.info);
      return;
    }
    setState(() {
      _busy = true;
      _progress = null;
      _result = null;
    });
    final result = await installer.install(
      release!,
      onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      },
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  String? get _message => switch (_result) {
    ApkInstallResult.started => 'Confirmez l’installation dans la fenêtre d’Android : Vixeo redémarre ensuite.',
    ApkInstallResult.permissionNeeded =>
      'Autorisez Vixeo à installer des applis (« Installer des applis inconnues »), revenez ici, puis réessayez.',
    ApkInstallResult.corrupted => 'Le fichier téléchargé est incorrect : il a été supprimé. Réessayez.',
    ApkInstallResult.failed => 'Téléchargement impossible. Vérifiez votre connexion et réessayez.',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final message = _message;
    final retry = _result != null && _result != ApkInstallResult.started;

    return Column(
      crossAxisAlignment: widget.expand ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_busy) ...[
          Text(
            _progress == null ? 'Préparation du téléchargement…' : 'Téléchargement… ${(_progress! * 100).round()} %',
            style: VxText.body(14 * s, color: VxColors.textSoft),
          ),
          SizedBox(height: 10 * s),
          ClipRRect(
            borderRadius: BorderRadius.circular(4 * s),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6 * s,
              color: VxColors.accent,
              backgroundColor: VxColors.surfaceHigh,
            ),
          ),
        ] else ...[
          if (message != null) ...[
            Text(message, style: VxText.body(14 * s, color: VxColors.textSoft)),
            SizedBox(height: 12 * s),
          ],
          VxButton(
            label: retry ? 'Réessayer' : 'Mettre à jour',
            icon: retry ? Icons.refresh_rounded : Icons.system_update_rounded,
            autofocus: widget.autofocus,
            expand: widget.expand,
            onPressed: _update,
          ),
          if (_result == ApkInstallResult.failed || _result == ApkInstallResult.corrupted)
            TextButton(
              onPressed: () => openUpdatePage(context, widget.info),
              child: const Text('Ouvrir la page de téléchargement'),
            ),
        ],
      ],
    );
  }
}

/// Wraps the whole app (`MaterialApp.router` builder): blocks with "Mise à jour nécessaire" when
/// the installed version is no longer accepted, suggests a newer one once per launch, and checks
/// again when the app comes back to the foreground (vixeo_backend/docs/mise-a-jour.md).
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.navigatorKey, required this.child});

  /// Navigator of the router: the "new version" dialog opens on top of the current page.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  late final AppLifecycleListener _lifecycle;

  /// Build already suggested during this launch.
  int? _suggested;

  /// A suggestion can arrive before the saved session has finished restoring.
  /// Keep it pending until GoRouter has completed its startup redirect.
  UpdateInfo? _pendingSuggestion;
  bool _dialogScheduledOrOpen = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(updateProvider.notifier).checkIfStale());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _maybeSuggest(UpdateInfo? info) {
    final latest = info?.latest;
    if (info == null || info.status != UpdateStatus.updateAvailable || latest == null) return;
    if (_suggested == latest.build) return;
    _pendingSuggestion = info;
    _showPendingSuggestionWhenReady();
  }

  void _showPendingSuggestionWhenReady() {
    if (!mounted || _dialogScheduledOrOpen || _pendingSuggestion == null) return;

    // Do not put a dialog on top of /demarrage: the session restoration redirect
    // immediately replaces that route and can dismiss the dialog.
    if (ref.read(sessionProvider).status == SessionStatus.restoring) return;

    final info = _pendingSuggestion!;
    final build = info.latest!.build;
    _pendingSuggestion = null;
    _suggested = build;
    _dialogScheduledOrOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _dialogScheduledOrOpen = false;
        return;
      }
      final context = widget.navigatorKey.currentContext;
      if (context == null) {
        _dialogScheduledOrOpen = false;
        _pendingSuggestion = info;
        return;
      }
      showUpdateAvailableDialog(context, info).whenComplete(() {
        _dialogScheduledOrOpen = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateProvider, (_, next) => _maybeSuggest(next.value));
    ref.listen(sessionProvider, (_, next) {
      if (next.status != SessionStatus.restoring) {
        _showPendingSuggestionWhenReady();
      }
    });
    final info = ref.watch(updateProvider).value;
    _maybeSuggest(info);

    if (info != null && info.status == UpdateStatus.updateRequired) {
      // Above the router: an Overlay of its own for tooltips and text selection.
      return Overlay(
        initialEntries: [OverlayEntry(builder: (_) => UpdateRequiredScreen(info: info))],
      );
    }
    return widget.child;
  }
}

/// "Nouvelle version disponible", once per launch. TV: "Mettre à jour" has the focus.
Future<void> showUpdateAvailableDialog(BuildContext context, UpdateInfo info) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Une mise à jour est disponible'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Il est important de garder Vixeo à jour pour profiter d’une expérience plus fluide, '
            'des dernières fonctionnalités et des améliorations de sécurité. '
            'Nous vous recommandons d’installer cette mise à jour.',
            style: VxText.body(15, color: VxColors.textSoft),
          ),
          const SizedBox(height: 20),
          UpdateButton(info: info, autofocus: true),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Plus tard'))],
  ),
);

/// Shown instead of the app while the installed version is older than a required release.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key, required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final installed = ref.watch(installedVersionProvider).value;
    final latest = info.latest;
    final notes = latest?.notes;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(32 * s),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 480 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: VxLogo(size: 30 * s)),
                SizedBox(height: 32 * s),
                Icon(Icons.system_update_rounded, size: 56 * s, color: VxColors.accent),
                SizedBox(height: 16 * s),
                Text('Mise à jour nécessaire', style: VxText.title(26 * s), textAlign: TextAlign.center),
                SizedBox(height: 10 * s),
                Text(
                  'Cette version de Vixeo${installed == null ? '' : ' (${installed.version})'} n’est plus prise en '
                  'charge. Installez la version ${latest?.version ?? 'la plus récente'} pour continuer.',
                  style: VxText.body(15 * s, color: VxColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                if (notes != null) ...[
                  SizedBox(height: 16 * s),
                  Text(
                    notes,
                    style: VxText.body(14 * s, color: VxColors.textSoft),
                    textAlign: TextAlign.center,
                  ),
                ],
                SizedBox(height: 28 * s),
                UpdateButton(info: info, autofocus: true, expand: true),
                SizedBox(height: 10 * s),
                VxButton(
                  label: 'Réessayer',
                  kind: VxButtonKind.outline,
                  expand: true,
                  onPressed: () => ref.read(updateProvider.notifier).check().catchError((_) => null),
                ),
                if (Legal.supportEmail.isNotEmpty) ...[
                  SizedBox(height: 20 * s),
                  Text(
                    'Besoin d’aide ? ${Legal.supportEmail}',
                    style: VxText.body(13 * s, color: VxColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

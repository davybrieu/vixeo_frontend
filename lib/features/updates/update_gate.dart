import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import 'updates.dart';

/// Opens the page where the update is installed: the Play Store app on Android (phones and TVs,
/// which have no browser), the website's download page on iOS. Returns false if nothing opened.
Future<bool> openUpdatePage(BuildContext context, UpdateInfo info) async {
  final url = info.updateUrl;
  var opened = false;
  if (url != null) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final id = uri.host == 'play.google.com' ? uri.queryParameters['id'] : null;
      if (id != null && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        opened = await launchUrl(Uri.parse('market://details?id=$id')).catchError((_) => false);
      }
      if (!opened) opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    }
  }
  if (!opened && context.mounted) {
    final where = defaultTargetPlatform == TargetPlatform.iOS ? 'depuis le site de Vixeo' : 'depuis le Play Store';
    showVxSnack(context, 'Installez la nouvelle version $where.', icon: Icons.system_update_rounded);
  }
  return opened;
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
    _suggested = latest.build;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = widget.navigatorKey.currentContext;
      if (context != null) showUpdateAvailableDialog(context, info);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateProvider, (_, next) => _maybeSuggest(next.value));
    final info = ref.watch(updateProvider).value;

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
    title: Text('Vixeo ${info.latest?.version ?? ''} est disponible'),
    content: SizedBox(
      width: 420,
      child: Text(
        info.latest?.notes ?? 'Une nouvelle version de Vixeo est disponible.',
        style: VxText.body(15, color: VxColors.textSoft),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Plus tard')),
      VxButton(
        label: 'Mettre à jour',
        icon: Icons.system_update_rounded,
        autofocus: true,
        onPressed: () {
          Navigator.pop(dialogContext);
          openUpdatePage(context, info);
        },
      ),
    ],
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
                VxButton(
                  label: 'Mettre à jour',
                  icon: Icons.system_update_rounded,
                  autofocus: true,
                  expand: true,
                  onPressed: () => openUpdatePage(context, info),
                ),
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

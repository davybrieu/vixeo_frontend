import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import 'update_banner.dart';
import 'update_button.dart';
import 'updates.dart';

/// Wraps the whole app (`MaterialApp.router` builder) and checks for updates at launch and when
/// the app comes back to the foreground (vixeo_backend/docs/mise-a-jour.md):
/// - version no longer accepted: "Mise à jour nécessaire" instead of the app;
/// - newer version: [UpdateBanner] at the top of every page, the pages below it.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  late final AppLifecycleListener _lifecycle;
  final _bannerButton = FocusNode(debugLabel: 'Update banner');
  late final _reachBanner = _ReachBannerAction(_bannerButton);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(updateProvider.notifier).checkIfStale());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _bannerButton.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(updateProvider).value;

    if (info != null && info.status == UpdateStatus.updateRequired) {
      // Above the router: an Overlay of its own for tooltips and text selection.
      return Overlay(
        initialEntries: [OverlayEntry(builder: (_) => UpdateRequiredScreen(info: info))],
      );
    }

    final banner = info != null && info.status == UpdateStatus.updateAvailable && info.latest != null;
    // Same widgets with or without the banner: the router and its pages are never rebuilt.
    return Column(
      children: [
        if (banner) UpdateBanner(info: info, focusNode: _bannerButton),
        Expanded(
          child: Actions(
            actions: {DirectionalFocusIntent: _reachBanner},
            // The banner already keeps clear of the status bar.
            child: MediaQuery.removePadding(context: context, removeTop: banner, child: widget.child),
          ),
        ),
      ],
    );
  }
}

/// TV remote: Up from the top of a page (nothing above) reaches the banner's button. Not from a
/// dialog or a menu, which keep the focus until closed.
class _ReachBannerAction extends DirectionalFocusOrFirstAction {
  _ReachBannerAction(this.banner);

  /// Attached (has a context) only while the banner is shown.
  final FocusNode banner;

  @override
  void invoke(DirectionalFocusIntent intent) {
    if (move(intent) || intent.direction != TraversalDirection.up) return;
    final context = FocusManager.instance.primaryFocus?.context;
    if (banner.context == null || !banner.canRequestFocus || context == null) return;
    if (ModalRoute.of(context) is PageRoute) banner.requestFocus();
  }
}

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

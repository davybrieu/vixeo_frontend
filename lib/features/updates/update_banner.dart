import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import 'apk_installer.dart';
import 'update_button.dart';
import 'updates.dart';

/// Top of every page while a newer version is available (placed by `UpdateGate`): "Une nouvelle
/// mise à jour est disponible" and "Télécharger" on the right. The download progress and its
/// outcome replace the text. TV remote: Up from the top of a page reaches the button, Down goes
/// back to the element of the page that had the focus.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key, required this.info, this.focusNode});

  final UpdateInfo info;

  /// The button, so that the gate can give it the focus.
  final FocusNode? focusNode;

  static final _background = Color.alphaBlend(VxColors.accent.withValues(alpha: 0.12), VxColors.surface);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = uiScale(context);
    final download = ref.watch(updateDownloadProvider);
    final text = download.busy
        ? updateProgressLabel(download.progress)
        : updateDownloadMessage(download) ?? 'Une nouvelle mise à jour est disponible';

    return Actions(
      actions: {
        // Only one button here: Down goes back to the page, the other arrows stay on it.
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.down) {
              // The focus scope remembers the element the page had before.
              FocusManager.instance.primaryFocus?.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
            }
            return null;
          },
        ),
      },
      child: Material(
        color: _background,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: VxColors.line)),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 12 * s, 8 * s),
                  child: Row(
                    children: [
                      Icon(Icons.system_update_rounded, color: VxColors.accent, size: 22 * s),
                      SizedBox(width: 12 * s),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(14 * s, weight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * s),
                      VxButton(
                        label: download.failed ? 'Réessayer' : 'Télécharger',
                        icon: download.failed ? Icons.refresh_rounded : Icons.download_rounded,
                        dense: true,
                        loading: download.busy,
                        focusNode: focusNode,
                        onPressed: () => startUpdate(context, ref, info),
                      ),
                    ],
                  ),
                ),
                if (download.busy)
                  LinearProgressIndicator(
                    value: download.progress,
                    minHeight: 3 * s,
                    color: VxColors.accent,
                    backgroundColor: Colors.transparent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

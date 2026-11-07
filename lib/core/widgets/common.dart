import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../device/layout.dart';
import '../theme.dart';
import 'focusable.dart';

/// "VIXEO" wordmark, the X in green.
class VxLogo extends StatelessWidget {
  const VxLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = VxText.title(size, weight: FontWeight.w800).copyWith(letterSpacing: size * 0.06, height: 1);
    return Semantics(
      label: 'Vixeo',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: style,
            children: const [
              TextSpan(text: 'VI'),
              TextSpan(
                text: 'X',
                style: TextStyle(color: VxColors.accent),
              ),
              TextSpan(text: 'EO'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Network image with a toned placeholder; [fallback] shows when there is no image.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, this.seed = 0, this.fallback, this.fit = BoxFit.cover});

  final String? url;
  final int seed;
  final Widget? fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: VxColors.tone(seed), child: fallback ?? const SizedBox.expand());
    if (url == null || url!.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => ColoredBox(color: VxColors.tone(seed)),
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

enum VxButtonKind { primary, secondary, outline, danger }

/// Button with the Vixeo look and a TV focus state.
class VxButton extends StatelessWidget {
  const VxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = VxButtonKind.primary,
    this.expand = false,
    this.loading = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final VxButtonKind kind;
  final bool expand;
  final bool loading;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final height = layout.isLarge ? layout.tv(76) : 52.0;
    final fontSize = layout.isLarge ? layout.tv(24) : 16.0;
    final radius = layout.isLarge ? layout.tv(18) : 12.0;

    final (bg, fg, border) = switch (kind) {
      VxButtonKind.primary => (VxColors.accent, VxColors.onAccent, null),
      VxButtonKind.secondary => (VxColors.text.withValues(alpha: 0.14), VxColors.text, null),
      VxButtonKind.outline => (Colors.transparent, VxColors.text, Border.all(color: VxColors.lineStrong, width: 1.5)),
      VxButtonKind.danger => (const Color(0xFFB42318), Colors.white, null),
    };
    final enabled = onPressed != null && !loading;

    return VxFocusable(
      onPressed: enabled ? onPressed : null,
      autofocus: autofocus,
      borderRadius: radius,
      onAccent: kind == VxButtonKind.primary || kind == VxButtonKind.danger,
      focusScale: 1.04,
      semanticLabel: label,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: layout.isLarge ? layout.tv(36) : 24),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius), border: border),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox.square(
                  dimension: fontSize,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: fontSize * 1.15, color: fg),
              if (loading || icon != null) SizedBox(width: fontSize * 0.5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(fontSize, weight: FontWeight.w600, color: fg, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round icon-only button, the same for every title action (Ma liste, Vu, Bande-annonce).
/// [label] is read by screen readers only. [active] = the state is on (in my list, watched).
class VxIconAction extends StatelessWidget {
  const VxIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.isLarge ? layout.tv(76) : 52.0;
    return VxFocusable(
      onPressed: onPressed,
      borderRadius: size,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? VxColors.accent.withValues(alpha: 0.16) : VxColors.text.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(icon, key: ValueKey(icon), color: active ? VxColors.accent : VxColors.text, size: size * 0.46),
        ),
      ),
    );
  }
}

/// "12+", "4K HDR"… [outlined] for age ratings.
class VxBadge extends StatelessWidget {
  const VxBadge(this.label, {super.key, this.outlined = false, this.accent = false, this.fontSize = 12});

  final String label;
  final bool outlined;
  final bool accent;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: fontSize * 0.2),
    decoration: BoxDecoration(
      color: accent ? VxColors.accent : (outlined ? null : VxColors.surfaceHigh),
      border: outlined ? Border.all(color: const Color(0xFF5A665E)) : null,
      borderRadius: BorderRadius.circular(fontSize * 0.4),
    ),
    child: Text(
      label,
      style: VxText.body(
        fontSize,
        weight: FontWeight.w700,
        color: accent ? VxColors.onAccent : VxColors.text,
        height: 1.2,
      ),
    ),
  );
}

/// Thin progress bar for "Continuer à regarder".
class VxProgressBar extends StatelessWidget {
  const VxProgressBar({super.key, required this.value, this.height = 4});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: VxColors.text.withValues(alpha: 0.22))),
        FractionallySizedBox(
          widthFactor: value.clamp(0, 1).toDouble(),
          child: const ColoredBox(color: VxColors.accent),
        ),
      ],
    ),
  );
}

/// Row title with an optional "Tout voir".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.padding});

  final String title;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.isLarge ? layout.tv(22) : 12),
      child: Text(title, style: VxText.title(layout.isLarge ? layout.tv(30) : 18)),
    );
  }
}

/// Error with a "Réessayer" button. Shows the API's French message.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException ? (error as ApiException).message : 'Une erreur est survenue.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: VxColors.textMuted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: VxText.body(16, color: VxColors.textSoft),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              VxButton(label: 'Réessayer', onPressed: onRetry, kind: VxButtonKind.secondary, autofocus: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Builds [data] once an async value has loaded; spinner meanwhile, [ErrorPanel] on error.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => switch (value) {
    AsyncData(:final value) => data(value),
    AsyncError(:final error) => ErrorPanel(error: error, onRetry: onRetry),
    _ => loading ?? const Center(child: CircularProgressIndicator()),
  };
}

/// Centered message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: VxColors.textMuted),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: VxText.title(20)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: VxText.body(15, color: VxColors.textSecondary),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Short alert at the bottom of the screen ("Supprimé de votre liste"…).
void showVxSnack(BuildContext context, String message, {IconData? icon}) =>
    showVxSnackOn(ScaffoldMessenger.of(context), message, icon: icon);

/// Same, when the screen that asked may already be closed.
void showVxSnackOn(ScaffoldMessengerState messenger, String message, {IconData? icon}) {
  // Readable from the sofa: bigger and centered on TV / large screens.
  final layout = Layout.of(messenger.context);
  final textSize = layout.isLarge ? layout.tv(24) : 15.0;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2500),
        width: layout.isLarge ? layout.tv(760) : null,
        padding: layout.isLarge ? EdgeInsets.symmetric(horizontal: layout.tv(28), vertical: layout.tv(22)) : null,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: VxColors.accent, size: textSize * 1.45),
              SizedBox(width: textSize * 0.8),
            ],
            Expanded(child: Text(message, style: VxText.body(textSize))),
          ],
        ),
      ),
    );
}


/// Shared search input used by catalog search and the personal library.
class VxSearchField extends StatelessWidget {
  const VxSearchField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.fontSize = 16,
    this.hintText = 'Films, séries, acteurs…',
    required this.onChanged,
    this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool autofocus;
  final double fontSize;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: color, width: width),
    );

    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (_, value, _) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: VxText.body(fontSize),
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: VxColors.background.withValues(alpha: 0.6),
          prefixIcon: const Icon(Icons.search_rounded, color: VxColors.textSecondary),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(tooltip: 'Effacer', icon: const Icon(Icons.close_rounded), onPressed: onClear),
          border: border(VxColors.line),
          enabledBorder: border(VxColors.line),
          focusedBorder: border(VxColors.accent, 2),
        ),
      ),
    );
  }
}

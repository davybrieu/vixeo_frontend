import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Opens the context menu: menu key on remotes / keyboards (long press on touch).
class _ContextMenuIntent extends Intent {
  const _ContextMenuIntent();
}

/// Anything the user can select with a finger, a mouse or a TV remote.
///
/// Flutter already moves the focus with the arrow keys and triggers
/// [ActivateIntent] with OK / Enter. This widget draws the Vixeo focus state:
/// a ring (green on dark elements, white on green ones) and a slight zoom,
/// only when the focus comes from a keyboard or a remote, not from a tap.
class VxFocusable extends StatefulWidget {
  const VxFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onFocused,
    this.onHovered,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = 12,
    this.onAccent = false,
    this.focusScale = 1.06,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;

  /// Long press (touch), or the menu key of a remote: context menu.
  final VoidCallback? onLongPress;

  /// Called when this element receives the focus (e.g. to update a TV hero).
  final VoidCallback? onFocused;

  /// Called when the mouse starts hovering this element (same use, with a mouse).
  final VoidCallback? onHovered;
  final bool autofocus;
  final FocusNode? focusNode;
  final double borderRadius;

  /// The element itself is green: draw a white ring.
  final bool onAccent;
  final double focusScale;
  final String? semanticLabel;

  @override
  State<VxFocusable> createState() => _VxFocusableState();
}

class _VxFocusableState extends State<VxFocusable> {
  bool _focused = false;
  bool _hovered = false;
  FocusNode? _ownNode;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: widget.semanticLabel));

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      // `autofocus` can be lost when the screen appears (e.g. on the web with
      // accessibility on): take the focus if nobody else has it once built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_node.hasFocus && !hasFocusedElement()) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null || widget.onLongPress != null;
    final ringColor = widget.onAccent ? VxColors.text : VxColors.accent;
    final scale = _focused ? widget.focusScale : (_hovered ? 1.02 : 1.0);

    return Semantics(
      button: widget.onPressed != null,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: interactive,
        focusNode: _node,
        autofocus: widget.autofocus,
        mouseCursor: widget.onPressed != null ? SystemMouseCursors.click : MouseCursor.defer,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.contextMenu): _ContextMenuIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonY): _ContextMenuIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _ContextMenuIntent: CallbackAction<_ContextMenuIntent>(
            onInvoke: (_) {
              widget.onLongPress?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onFocusChange: (focused) {
          if (focused) widget.onFocused?.call();
        },
        // The mouse enters the element, whatever the highlight mode (touch or keyboard).
        child: MouseRegion(
          onEnter: widget.onHovered == null ? null : (_) => widget.onHovered!(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onLongPress: widget.onLongPress,
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(color: _focused ? ringColor : Colors.transparent, width: 3.5),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// True when an actual element (not just a screen's focus scope) has the focus.
bool hasFocusedElement() {
  final primary = FocusManager.instance.primaryFocus;
  return primary != null && primary is! FocusScopeNode;
}

/// Arrow keys: move the focus; when nothing has it yet (screen just opened),
/// give it to the first element of the screen instead of doing nothing.
class DirectionalFocusOrFirstAction extends Action<DirectionalFocusIntent> {
  @override
  void invoke(DirectionalFocusIntent intent) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    if (primary is FocusScopeNode && primary.focusedChild == null) {
      primary.nextFocus();
      return;
    }
    primary.focusInDirection(intent.direction);
  }
}

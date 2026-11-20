import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../device/layout.dart';
import 'focusable.dart';

// Navigation with the arrow keys of a TV remote (D-pad) or a keyboard, for the whole app:
//  * one traversal policy everywhere ([vxTraversalPolicy]): Flutter's spatial moves, with their
//    memory (Down then Up comes back to the same card, whatever the row), and no scrolling of its
//    own: [RemoteNavigation] scrolls once, smoothly, to the element that got the focus;
//  * a held key (key repeat) is known ([RemoteKeys.repeating]): the scrolling is shorter and the
//    TV hero waits for the focus to stop (catalog/hero.dart) instead of loading every image;
//  * Up / Down leave a one-line text field (Flutter would move the caret to its start / end and
//    keep the focus there);
//  * [EdgeDirectionalFocusAction]: what an arrow does at the edge of a region (the rail and the
//    pages beside it, shell/app_shell.dart).

/// The traversal policy of every [FocusTraversalGroup] of the app. One instance: the memory of the
/// moves is kept across the rows (each row is a group).
final FocusTraversalPolicy vxTraversalPolicy = ReadingOrderTraversalPolicy(requestFocusCallback: _requestFocus);

/// Focuses [node]. On a TV, [RemoteNavigation] then scrolls to it (centred, animated). Elsewhere,
/// the smallest scroll that shows it, animated (Flutter's default jumps, which jolts).
void _requestFocus(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final context = node.context;
  if (DeviceInfo.isTv || context == null) return;
  Scrollable.ensureVisible(
    context,
    alignment: alignment ?? 1,
    alignmentPolicy: alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit,
    duration: duration ?? const Duration(milliseconds: 160),
    curve: curve ?? Curves.easeOutCubic,
  );
}

/// The remote's keys as they are pressed: [repeating] while an arrow (or any key) is held down.
abstract final class RemoteKeys {
  static bool _installed = false;
  static bool _repeating = false;

  /// A key is held down: its events repeat.
  static bool get repeating => _repeating;

  static void ensureInitialized() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(onKey);
  }

  /// Every key event of the app (never handled here: it goes on to the focused element).
  @visibleForTesting
  static bool onKey(KeyEvent event) {
    _repeating = event is KeyRepeatEvent;
    return false;
  }

  @visibleForTesting
  static set repeating(bool value) => _repeating = value;
}

/// Arrow keys inside a region of the screen: the usual move and, when nothing is in that
/// direction inside the region, [onEdge] (e.g. Left on the first card of a row: the rail). An edge
/// [onEdge] doesn't handle (returns false) goes to what is around the region ([outer]: e.g. Up at
/// the top of a page reaches the update banner, updates/update_gate.dart).
class EdgeDirectionalFocusAction extends DirectionalFocusOrFirstAction {
  EdgeDirectionalFocusAction(this.onEdge, {this.outer});

  final bool Function(TraversalDirection direction) onEdge;

  /// A context above the region's [Actions].
  final BuildContext? outer;

  @override
  void invoke(DirectionalFocusIntent intent) {
    if (move(intent) || onEdge(intent.direction)) return;
    final context = outer;
    if (context != null && context.mounted) Actions.maybeInvoke(context, intent);
  }
}

/// Up / Down in a one-line text field: to the element above / below.
class _LeaveTextFieldIntent extends Intent {
  const _LeaveTextFieldIntent(this.direction);

  final TraversalDirection direction;
}

class _LeaveTextFieldAction extends Action<_LeaveTextFieldIntent> {
  static EditableText? get _field {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    final widget = context.widget;
    return widget is EditableText ? widget : context.findAncestorWidgetOfExactType<EditableText>();
  }

  /// Only a one-line field: in a longer one, the arrows go from line to line. Disabled, the key
  /// goes on to the field (and outside a field, to the usual arrow keys).
  @override
  bool isEnabled(_LeaveTextFieldIntent intent) => _field?.maxLines == 1;

  @override
  void invoke(_LeaveTextFieldIntent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;
    Actions.maybeInvoke(context, DirectionalFocusIntent(intent.direction, ignoreTextFields: false));
  }
}

/// Put once around the app's pages (`MaterialApp.builder`): the policy, the text fields' Up / Down
/// and, on a TV, the scrolling that keeps the focused element in view.
class RemoteNavigation extends StatefulWidget {
  const RemoteNavigation({super.key, required this.child});

  final Widget child;

  /// Where the focused element ends up on a TV: a bit above the middle of each list (rows and
  /// pages), whatever the direction.
  static const alignment = 0.42;

  @override
  State<RemoteNavigation> createState() => _RemoteNavigationState();
}

class _RemoteNavigationState extends State<RemoteNavigation> {
  FocusNode? _revealed;

  @override
  void initState() {
    super.initState();
    RemoteKeys.ensureInitialized();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  /// One smooth scroll per focus change, through every list around the element (its row, then its
  /// page): no jump first (see [vxTraversalPolicy]). Shorter while a key is held, so the lists
  /// keep up with the focus.
  void _onFocusChange() {
    if (!DeviceInfo.isTv) return;
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode || identical(node, _revealed)) return;
    _revealed = node;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || !node.hasPrimaryFocus || context == null || !context.mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: RemoteNavigation.alignment,
        duration: Duration(milliseconds: RemoteKeys.repeating ? 110 : 220),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: vxTraversalPolicy,
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): _LeaveTextFieldIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown): _LeaveTextFieldIntent(TraversalDirection.down),
      },
      child: Actions(
        actions: {_LeaveTextFieldIntent: _LeaveTextFieldAction()},
        child: widget.child,
      ),
    ),
  );
}

/// Holds back a value while a key is held down (the focus runs along a row): the last one is given
/// once the focus stops for [delay]. Otherwise, at once.
class RepeatSettler<T> {
  RepeatSettler(this.apply, {this.delay = const Duration(milliseconds: 160)});

  final void Function(T value) apply;
  final Duration delay;
  Timer? _timer;

  void add(T value) {
    _timer?.cancel();
    if (!RemoteKeys.repeating) {
      apply(value);
      return;
    }
    _timer = Timer(delay, () => apply(value));
  }

  void cancel() => _timer?.cancel();
}

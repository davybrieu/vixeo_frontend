import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../device/layout.dart';
import '../theme.dart';
import 'common.dart';
import 'focus_navigation.dart';

/// Moves the active thumb of a [VxRangeSlider] (Left / Right of a keyboard or a remote).
class _MoveThumbIntent extends Intent {
  const _MoveThumbIntent(this.direction);

  final int direction;
}

/// Slider with two thumbs: the start and the end of a range (search filters « Années », « Note »,
/// « Votants », developer's request, 21/11/2026). Positions are indexes, 0 to [count] - 1: the
/// caller turns them into values (`RangeStops`).
///
/// Finger or mouse: the nearest thumb follows (a tap moves it there; when both thumbs are at the
/// same place, the direction of the drag chooses). Keyboard or remote: one focus stop, Left / Right
/// move the active thumb (faster while the key is held), OK switches to the other one; the active
/// thumb has the focus ring, Up / Down leave the slider.
class VxRangeSlider extends StatefulWidget {
  const VxRangeSlider({
    super.key,
    required this.count,
    required this.values,
    required this.onChanged,
    required this.label,
    required this.valueLabel,
    this.autofocus = false,
  }) : assert(count >= 2);

  /// Number of positions.
  final int count;

  /// Start and end positions (start ≤ end).
  final (int, int) values;
  final ValueChanged<(int, int)> onChanged;

  /// Name read by screen readers (« Années »).
  final String label;

  /// Text of a position (« 2010 »), read by screen readers.
  final String Function(int index) valueLabel;
  final bool autofocus;

  @override
  State<VxRangeSlider> createState() => _VxRangeSliderState();
}

class _VxRangeSliderState extends State<VxRangeSlider> {
  final _node = FocusNode(debugLabel: 'VxRangeSlider');

  /// The thumb the keys move: false = start, true = end.
  bool _endActive = false;

  /// Keyboard or remote focus (not a tap): the ring is drawn.
  bool _highlighted = false;

  /// The thumb being dragged; null while the direction must choose (both thumbs at one place).
  bool? _dragEnd;
  double _dragOrigin = 0;

  int get _start => widget.values.$1;
  int get _end => widget.values.$2;
  int get _last => widget.count - 1;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      // Like VxFocusable: `autofocus` can be lost when the window appears.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _node.hasFocus) return;
        final focused = FocusScope.of(context).focusedChild;
        if (focused != null && focused.hasFocus) return;
        _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Moves one thumb, never past the other.
  void _set(bool end, int index) {
    final i = index.clamp(0, _last);
    final next = end ? (_start, math.max(i, _start)) : (math.min(i, _end), _end);
    if (next != widget.values) widget.onChanged(next);
  }

  void _move(int direction) {
    // Held down: about 30 steps from one end to the other.
    final step = RemoteKeys.repeating ? math.max(1, (widget.count / 30).round()) : 1;
    _set(_endActive, (_endActive ? _end : _start) + direction * step);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    final thumb = 11 * s;
    final height = 48 * s;

    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveThumbIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _MoveThumbIntent(1),
      },
      actions: {
        _MoveThumbIntent: CallbackAction<_MoveThumbIntent>(onInvoke: (intent) => _move(intent.direction)),
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => setState(() => _endActive = !_endActive),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => setState(() => _endActive = !_endActive),
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _highlighted = value),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final inset = thumb * 1.4;
          final span = math.max(1.0, width - 2 * inset);
          double xOf(int index) => inset + span * index / _last;
          int indexAt(double x) => (((x - inset) / span) * _last).round().clamp(0, _last);

          /// The thumb nearest to [x]; null when both are there (the drag's direction chooses).
          bool? nearestIsEnd(double x) {
            if (_start == _end) {
              final at = xOf(_start);
              if ((x - at).abs() < 1) return null;
              return x > at;
            }
            return (x - xOf(_end)).abs() <= (x - xOf(_start)).abs();
          }

          void drag(bool end, double x) {
            if (_endActive != end) setState(() => _endActive = end);
            _set(end, indexAt(x));
          }

          Widget thumbSemantics(bool end) {
            final index = end ? _end : _start;
            return Positioned(
              left: xOf(index) - thumb,
              top: height / 2 - thumb,
              width: thumb * 2,
              height: thumb * 2,
              child: Semantics(
                slider: true,
                label: '${widget.label}, ${end ? 'fin' : 'début'}',
                value: widget.valueLabel(index),
                increasedValue: widget.valueLabel(math.min(index + 1, _last)),
                decreasedValue: widget.valueLabel(math.max(index - 1, 0)),
                onIncrease: () => _set(end, index + 1),
                onDecrease: () => _set(end, index - 1),
                child: const SizedBox.expand(),
              ),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (details) {
              final end = nearestIsEnd(details.localPosition.dx);
              if (end != null) drag(end, details.localPosition.dx);
            },
            onHorizontalDragStart: (details) {
              _dragOrigin = details.localPosition.dx;
              _dragEnd = nearestIsEnd(_dragOrigin);
            },
            onHorizontalDragUpdate: (details) {
              final x = details.localPosition.dx;
              if (_dragEnd == null && x != _dragOrigin) _dragEnd = x > _dragOrigin;
              final end = _dragEnd;
              if (end != null) drag(end, x);
            },
            onHorizontalDragEnd: (_) => _dragEnd = null,
            onHorizontalDragCancel: () => _dragEnd = null,
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RangePainter(
                        start: xOf(_start),
                        end: xOf(_end),
                        from: inset,
                        to: inset + span,
                        thumb: thumb,
                        track: 4 * s,
                        endActive: _endActive,
                        ring: _highlighted,
                      ),
                    ),
                  ),
                  thumbSemantics(false),
                  thumbSemantics(true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter({
    required this.start,
    required this.end,
    required this.from,
    required this.to,
    required this.thumb,
    required this.track,
    required this.endActive,
    required this.ring,
  });

  /// Positions of the thumbs and ends of the track.
  final double start;
  final double end;
  final double from;
  final double to;
  final double thumb;
  final double track;
  final bool endActive;

  /// Focus ring around the active thumb.
  final bool ring;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final radius = Radius.circular(track / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(from, y - track / 2, to, y + track / 2, radius),
      Paint()..color = VxColors.lineStrong,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(start, y - track / 2, end, y + track / 2, radius),
      Paint()..color = VxColors.accent,
    );

    void drawThumb(double x, {required bool active}) {
      final r = active && ring ? thumb * 1.12 : thumb;
      // A dark edge: two thumbs at the same place stay distinct.
      canvas.drawCircle(Offset(x, y), r + 2, Paint()..color = VxColors.surface);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = VxColors.accent);
      if (active && ring) {
        // White on a green element, like VxFocusable.
        canvas.drawCircle(
          Offset(x, y),
          r + 5,
          Paint()
            ..color = VxColors.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5,
        );
      }
    }

    // The active thumb on top.
    drawThumb(endActive ? start : end, active: false);
    drawThumb(endActive ? end : start, active: true);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.start != start ||
      old.end != end ||
      old.from != from ||
      old.to != to ||
      old.thumb != thumb ||
      old.track != track ||
      old.endActive != endActive ||
      old.ring != ring;
}

/// A range chosen with a [VxRangeSlider] (search filters « Années », « Note », « Votants »):
/// bottom sheet on a phone, dialog on larger screens, like `showVxChoice`. [summary] describes the
/// range being chosen (« Depuis 2010 »), [valueLabel] the positions (ends of the track, screen
/// readers). « Réinitialiser » moves the thumbs to both ends (no limit), « Appliquer » returns the
/// positions; null when closed without applying.
Future<(int, int)?> showVxRange(
  BuildContext context, {
  required String title,
  required int count,
  required (int, int) selected,
  required String Function(int index) valueLabel,
  required String Function(int start, int end) summary,
}) {
  final layout = Layout.of(context);
  Widget picker() => _RangePicker(
    title: title,
    count: count,
    selected: selected,
    valueLabel: valueLabel,
    summary: summary,
  );

  if (layout.isPhone) {
    return showModalBottomSheet<(int, int)>(
      // Above the phone's tab bar, drawn over the pages' navigator (AppShell).
      useRootNavigator: true,
      context: context,
      backgroundColor: VxColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: picker()),
    );
  }
  return showDialog<(int, int)>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: VxColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.isLarge ? layout.tv(760) : 480),
        child: picker(),
      ),
    ),
  );
}

class _RangePicker extends StatefulWidget {
  const _RangePicker({
    required this.title,
    required this.count,
    required this.selected,
    required this.valueLabel,
    required this.summary,
  });

  final String title;
  final int count;
  final (int, int) selected;
  final String Function(int index) valueLabel;
  final String Function(int start, int end) summary;

  @override
  State<_RangePicker> createState() => _RangePickerState();
}

class _RangePickerState extends State<_RangePicker> {
  late (int, int) _values = widget.selected;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    final muted = VxText.body(13 * s, color: VxColors.textMuted);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24 * s, layout.isPhone ? 0 : 24 * s, 24 * s, 20 * s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: VxText.title(20 * s)),
          SizedBox(height: 6 * s),
          // Read again by screen readers when it changes.
          Semantics(
            liveRegion: true,
            child: Text(
              widget.summary(_values.$1, _values.$2),
              style: VxText.body(16 * s, weight: FontWeight.w600, color: VxColors.accent),
            ),
          ),
          SizedBox(height: 12 * s),
          VxRangeSlider(
            count: widget.count,
            values: _values,
            onChanged: (values) => setState(() => _values = values),
            label: widget.title,
            valueLabel: widget.valueLabel,
            autofocus: true,
          ),
          ExcludeSemantics(
            child: Row(
              children: [
                Text(widget.valueLabel(0), style: muted),
                const Spacer(),
                Text(widget.valueLabel(widget.count - 1), style: muted),
              ],
            ),
          ),
          if (DeviceInfo.isTv) ...[
            SizedBox(height: 10 * s),
            Text('Gauche / droite : déplacer le curseur · OK : passer à l’autre curseur', style: muted),
          ],
          SizedBox(height: 20 * s),
          Row(
            children: [
              Expanded(
                child: VxButton(
                  label: 'Réinitialiser',
                  kind: VxButtonKind.outline,
                  expand: true,
                  onPressed: () => setState(() => _values = (0, widget.count - 1)),
                ),
              ),
              SizedBox(width: 12 * s),
              Expanded(
                child: VxButton(
                  label: 'Appliquer',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(_values),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

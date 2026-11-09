import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/widgets.dart';
import 'tmdb.dart';

/// Rates [target] (or changes / removes its rating and comment) in a dialog, saves the rating on
/// TMDb and the comment at Vixeo through the API, then confirms with an alert ("Note enregistrée :
/// 8/10", "Note supprimée").
Future<void> editRating(
  BuildContext context, {
  required RatingTarget target,
  required String name,
  String? subtitle,
  MyRating? current,
}) async {
  final choice = await showRatingDialog(context, name: name, subtitle: subtitle, current: current);
  if (choice == null || !context.mounted) return;
  final (rating,) = choice;
  final ratings = ProviderScope.containerOf(context, listen: false).read(tmdbRatingsProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (rating == null) {
      await ratings.remove(target);
      showVxSnackOn(messenger, 'Note supprimée', icon: Icons.star_outline_rounded);
    } else {
      await ratings.rate(target, rating);
      showVxSnackOn(messenger, 'Note enregistrée : ${formatScore(rating.value)}/10', icon: Icons.star_rounded);
    }
  } on ApiException catch (e) {
    showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
  }
}

/// Rating dialog: 10 stars, by half points (TMDb scale, 0.5 to 10), and an optional comment kept by
/// Vixeo. Returns `(rating,)` to save, `(null,)` to remove the current rating, null when closed. TV:
/// the stars have the focus, ← → change the rating, OK saves.
Future<(MyRating?,)?> showRatingDialog(
  BuildContext context, {
  required String name,
  String? subtitle,
  MyRating? current,
}) => showDialog<(MyRating?,)>(
  context: context,
  builder: (_) => _RatingDialog(name: name, subtitle: subtitle, current: current),
);

class _RatingDialog extends StatefulWidget {
  const _RatingDialog({required this.name, this.subtitle, this.current});

  final String name;
  final String? subtitle;
  final MyRating? current;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  /// Longest comment (the API's limit).
  static const maxComment = 2000;

  late double _value = widget.current?.value ?? 0;
  late final _comment = TextEditingController(text: widget.current?.comment ?? '');

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _save() {
    final comment = _comment.text.trim();
    if (_value > 0) Navigator.of(context).pop((MyRating(_value, comment: comment.isEmpty ? null : comment),));
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;

    return Dialog(
      backgroundColor: VxColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480 * s),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.current == null ? 'Noter' : 'Modifier mon avis',
                style: VxText.body(14 * s, color: VxColors.textSecondary),
              ),
              SizedBox(height: 4 * s),
              Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: VxText.title(22 * s)),
              if (widget.subtitle != null) ...[
                SizedBox(height: 2 * s),
                Text(widget.subtitle!, style: VxText.body(14 * s, color: VxColors.textSoft)),
              ],
              SizedBox(height: 22 * s),
              Text(
                _value == 0 ? '– / 10' : '${formatScore(_value)} / 10',
                textAlign: TextAlign.center,
                style: VxText.title(
                  34 * s,
                  weight: FontWeight.w800,
                  color: _value == 0 ? VxColors.textMuted : VxColors.accent,
                ),
              ),
              SizedBox(height: 10 * s),
              RatingStars(
                value: _value,
                starSize: 30 * s,
                autofocus: true,
                onChanged: (value) => setState(() => _value = value),
                onSubmitted: _save,
              ),
              SizedBox(height: 8 * s),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6 * s,
                children: [
                  Text('Votre note est enregistrée sur', style: VxText.body(12 * s, color: VxColors.textMuted)),
                  TmdbLogo(height: 9 * s),
                ],
              ),
              SizedBox(height: 18 * s),
              TextField(
                controller: _comment,
                minLines: 2,
                maxLines: 5,
                maxLength: maxComment,
                textCapitalization: TextCapitalization.sentences,
                style: VxText.body(15 * s),
                decoration: InputDecoration(
                  labelText: 'Commentaire (facultatif)',
                  hintText: 'Ce que vous en avez pensé…',
                  helperText: 'Gardé dans Vixeo, il n’est pas publié sur TMDb.',
                  helperMaxLines: 2,
                  counterText: '',
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: 18 * s),
              VxButton(
                label: 'Enregistrer',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: _value > 0 ? _save : null,
              ),
              if (widget.current != null) ...[
                SizedBox(height: 10 * s),
                VxButton(
                  label: 'Supprimer mon avis',
                  icon: Icons.delete_outline_rounded,
                  kind: VxButtonKind.outline,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop((null,)),
                ),
              ],
              SizedBox(height: 10 * s),
              VxButton(
                label: 'Annuler',
                kind: VxButtonKind.secondary,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 10 stars, by half points: tap or drag (finger, mouse), ← → (remote, keyboard), digits 1-9 and
/// 0 (= 10). OK / Enter calls [onSubmitted]. Read as a slider by screen readers.
class RatingStars extends StatefulWidget {
  const RatingStars({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.starSize = 30,
    this.autofocus = false,
  });

  /// 0 (nothing chosen) or 0.5 to 10.
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onSubmitted;
  final double starSize;
  final bool autofocus;

  @override
  State<RatingStars> createState() => _RatingStarsState();
}

class _RatingStarsState extends State<RatingStars> {
  /// The last value sent: several key presses can come before the next frame.
  late double _value = widget.value;

  static final _digits = {
    LogicalKeyboardKey.digit1: 1.0,
    LogicalKeyboardKey.digit2: 2.0,
    LogicalKeyboardKey.digit3: 3.0,
    LogicalKeyboardKey.digit4: 4.0,
    LogicalKeyboardKey.digit5: 5.0,
    LogicalKeyboardKey.digit6: 6.0,
    LogicalKeyboardKey.digit7: 7.0,
    LogicalKeyboardKey.digit8: 8.0,
    LogicalKeyboardKey.digit9: 9.0,
    LogicalKeyboardKey.digit0: 10.0,
  };

  late final _arrows = _RatingArrows(onStep: (delta) => _set(_value + delta));

  @override
  void didUpdateWidget(RatingStars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.value;
  }

  void _set(double value) {
    _value = value.clamp(0.5, 10).toDouble();
    widget.onChanged(_value);
  }

  /// Half points from the position on the row of stars.
  void _pick(double dx, double width) => _set(((dx / width) * 20).ceil().clamp(1, 20) / 2);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Narrow dialog (phone): smaller stars, never wider than the room.
    builder: (context, constraints) => _stars(math.min(widget.starSize, constraints.maxWidth / 10.4)),
  );

  Widget _stars(double size) {
    final value = widget.value;
    final width = size * 10;
    return Semantics(
      slider: true,
      label: 'Note sur 10',
      value: value == 0 ? 'aucune' : formatScore(value),
      increasedValue: formatScore((value + 0.5).clamp(0.5, 10)),
      decreasedValue: formatScore((value - 0.5).clamp(0.5, 10)),
      onIncrease: () => _set(_value + 0.5),
      onDecrease: () => _set(_value - 0.5),
      excludeSemantics: true,
      child: Actions(
        // ← → change the rating; ↑ ↓ still move between the dialog's buttons.
        actions: {DirectionalFocusIntent: _arrows},
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            final digit = _digits[event.logicalKey];
            if (digit == null || event is KeyUpEvent) return KeyEventResult.ignored;
            _set(digit);
            return KeyEventResult.handled;
          },
          child: Center(
            child: VxFocusable(
              autofocus: widget.autofocus,
              borderRadius: size * 0.4,
              focusScale: 1.02,
              onPressed: widget.onSubmitted ?? () {},
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition.dx, width),
                // Takes the tap: a tap on the stars chooses, it doesn't submit.
                onTapUp: (_) {},
                onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, width),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: size * 0.2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 1; i <= 10; i++)
                        Icon(
                          value >= i
                              ? Icons.star_rounded
                              : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
                          size: size,
                          color: value >= i - 0.5 ? VxColors.accent : VxColors.lineStrong,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingArrows extends DirectionalFocusOrFirstAction {
  _RatingArrows({required this.onStep});

  final void Function(double delta) onStep;

  @override
  void invoke(DirectionalFocusIntent intent) => switch (intent.direction) {
    TraversalDirection.left => onStep(-0.5),
    TraversalDirection.right => onStep(0.5),
    _ => move(intent),
  };
}

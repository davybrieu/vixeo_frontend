import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';

/// Checks a code typed on [showPinPad]: null when right (the pad closes), else the message to
/// show (the pad is emptied).
typedef PinCheck = Future<String?> Function(String pin);

/// The 4-digit keypad of the profiles (« Qui regarde ? », « Modifier le profil »): a title, a
/// line, four dots, the digits 0 to 9 and « Effacer ». Works by touch, with the remote (focus
/// moves between the keys, OK presses) and with the keyboard's or the remote's digit keys.
/// [confirm]: the code is typed twice (a new code). Returns the code checked, null when closed.
Future<String?> showPinPad(
  BuildContext context, {
  required String title,
  required String subtitle,
  required PinCheck onSubmit,
  bool confirm = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PinPad(title: title, subtitle: subtitle, onSubmit: onSubmit, confirm: confirm),
);

class _PinPad extends StatefulWidget {
  const _PinPad({required this.title, required this.subtitle, required this.onSubmit, required this.confirm});

  final String title;
  final String subtitle;
  final PinCheck onSubmit;
  final bool confirm;

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  static const length = 4;

  String _digits = '';

  /// The new code typed once ([confirm]): the second time must match.
  String? _first;
  String? _error;
  bool _checking = false;

  String get _subtitle => _first != null ? 'Saisissez-le une seconde fois' : widget.subtitle;

  void _add(String digit) {
    if (_checking || _digits.length >= length) return;
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == length) _complete();
  }

  void _erase() {
    if (_checking || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _complete() async {
    final pin = _digits;
    if (widget.confirm && _first == null) {
      setState(() {
        _first = pin;
        _digits = '';
      });
      return;
    }
    if (widget.confirm && pin != _first) {
      setState(() {
        _first = null;
        _digits = '';
        _error = 'Les deux codes ne correspondent pas. Recommencez.';
      });
      return;
    }
    setState(() => _checking = true);
    final error = await widget.onSubmit(pin);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(pin);
      return;
    }
    setState(() {
      _checking = false;
      _digits = '';
      _first = null;
      _error = error;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final digit = _digitOf(key);
    if (digit != null) {
      _add(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String? _digitOf(LogicalKeyboardKey key) {
    const digits = [
      [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0],
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
      [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
      [LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad5],
      [LogicalKeyboardKey.digit6, LogicalKeyboardKey.numpad6],
      [LogicalKeyboardKey.digit7, LogicalKeyboardKey.numpad7],
      [LogicalKeyboardKey.digit8, LogicalKeyboardKey.numpad8],
      [LogicalKeyboardKey.digit9, LogicalKeyboardKey.numpad9],
    ];
    for (final (value, keys) in digits.indexed) {
      if (keys.contains(key)) return '$value';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final layout = Layout.of(context);
    final key = layout.isLarge ? layout.tv(84) : 64.0;
    final gap = 12 * s;

    Widget digit(String value, {bool autofocus = false}) => _Key(
      size: key,
      label: value,
      autofocus: autofocus,
      onPressed: () => _add(value),
      child: Text(value, style: VxText.title(key * 0.38)),
    );

    return Focus(
      onKeyEvent: _onKey,
      child: Dialog(
        backgroundColor: VxColors.surface,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24 * s, 28 * s, 24 * s, 24 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, textAlign: TextAlign.center, style: VxText.title(20 * s)),
              SizedBox(height: 4 * s),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: VxText.body(14 * s, color: VxColors.textSecondary),
              ),
              SizedBox(height: 20 * s),
              Semantics(
                label: '${_digits.length} chiffres saisis sur $length',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < length; i++)
                      Container(
                        width: 14 * s,
                        height: 14 * s,
                        margin: EdgeInsets.symmetric(horizontal: 8 * s),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _digits.length ? VxColors.text : Colors.transparent,
                          border: Border.all(color: i < _digits.length ? VxColors.text : VxColors.lineStrong, width: 2),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 44 * s,
                child: Center(
                  child: _checking
                      ? SizedBox.square(dimension: 20 * s, child: const CircularProgressIndicator(strokeWidth: 2.4))
                      : _error == null
                      ? null
                      : Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: VxText.body(13 * s, color: VxColors.error),
                        ),
                ),
              ),
              FocusTraversalGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (row, values) in const [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                    ].indexed) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, value) in values.indexed) ...[
                            if (i > 0) SizedBox(width: gap),
                            digit(value, autofocus: row == 0 && i == 0),
                          ],
                        ],
                      ),
                      SizedBox(height: gap),
                    ],
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: key + gap),
                        digit('0'),
                        SizedBox(width: gap),
                        _Key(
                          size: key,
                          label: 'Effacer',
                          onPressed: _erase,
                          filled: false,
                          child: Icon(Icons.backspace_outlined, size: key * 0.34, color: VxColors.textSoft),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12 * s),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.size,
    required this.label,
    required this.onPressed,
    required this.child,
    this.autofocus = false,
    this.filled = true,
  });

  final double size;
  final String label;
  final VoidCallback onPressed;
  final Widget child;
  final bool autofocus;
  final bool filled;

  @override
  Widget build(BuildContext context) => VxFocusable(
    autofocus: autofocus,
    borderRadius: size,
    semanticLabel: label,
    onPressed: onPressed,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? VxColors.text.withValues(alpha: 0.08) : Colors.transparent,
      ),
      child: ExcludeSemantics(child: child),
    ),
  );
}

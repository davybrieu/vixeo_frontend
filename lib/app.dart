import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/widgets/focusable.dart';
import 'router.dart';

/// Same keys everywhere (TV remote, keyboard, web): arrows move the focus,
/// OK / Enter / Space activate. On the web Flutter would otherwise scroll with
/// the arrows and only activate Material buttons with Enter.
final Map<ShortcutActivator, Intent> remoteShortcuts = {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowLeft): const DirectionalFocusIntent(TraversalDirection.left),
  const SingleActivator(LogicalKeyboardKey.arrowRight): const DirectionalFocusIntent(TraversalDirection.right),
  const SingleActivator(LogicalKeyboardKey.arrowUp): const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.arrowDown): const DirectionalFocusIntent(TraversalDirection.down),
};

/// Arrow keys also work when the screen has just opened and nothing has the focus.
final Map<Type, Action<Intent>> remoteActions = {
  ...WidgetsApp.defaultActions,
  DirectionalFocusIntent: DirectionalFocusOrFirstAction(),
};

class VixeoApp extends ConsumerWidget {
  const VixeoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Vixeo',
    debugShowCheckedModeBanner: false,
    theme: buildVixeoTheme(),
    themeMode: ThemeMode.dark,
    routerConfig: ref.watch(routerProvider),
    shortcuts: remoteShortcuts,
    actions: remoteActions,
    locale: const Locale('fr', 'FR'),
    supportedLocales: const [Locale('fr', 'FR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // Rows can also be dragged with a mouse (web, Chromebook).
    scrollBehavior: const MaterialScrollBehavior().copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
    ),
  );
}

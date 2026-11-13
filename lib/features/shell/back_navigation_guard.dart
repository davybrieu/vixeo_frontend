import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';

/// Intercepts system Back (Android, TV remote) inside a route: from a sub-page, back to the
/// entry page (Home, or sign-in before signing in); from an entry page, the exit confirmation.
/// Without it, Back from the sign-in page went to /accueil, which redirects to /connexion: the
/// app could not be left with Back.
class BackNavigationGuard extends StatelessWidget {
  const BackNavigationGuard({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  /// Pages Back leaves the app from (after confirmation).
  static const _entryPages = {'/accueil', '/connexion', '/profils', '/demarrage'};

  /// Sign-in pages Back returns to the sign-in form from.
  static const _signInPages = {'/inscription', '/mot-de-passe-oublie'};

  /// Moves the focus off the text field being edited, if any: to the element under it, or to
  /// nothing. True when a field had the focus.
  static bool leaveTextField() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null) return false;
    if (context.widget is! EditableText && context.findAncestorWidgetOfExactType<EditableText>() == null) {
      return false;
    }
    if (!focus.focusInDirection(TraversalDirection.down)) focus.unfocus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final path = Uri.parse(location).path;
    final isEntry = _entryPages.contains(path);

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // On a TV, Back while a text field has the focus only leaves the field (which closes
        // the on-screen keyboard): it must not also leave the page.
        if (DeviceInfo.isTv && leaveTextField()) return;

        if (!isEntry) {
          context.go(_signInPages.contains(path) ? '/connexion' : '/accueil');
          return;
        }

        final shouldQuit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Êtes-vous sûr de vouloir quitter l'application ?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Rester sur l’application'),
              ),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Quitter')),
            ],
          ),
        );

        if (shouldQuit == true) await SystemNavigator.pop();
      },
      child: child,
    );
  }
}

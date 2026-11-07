import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Intercepts system Back inside a route, so the app can always return Home
/// before showing the explicit exit confirmation.
class BackNavigationGuard extends StatelessWidget {
  const BackNavigationGuard({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isHome = Uri.parse(location).path == '/accueil';

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (!isHome) {
          context.go('/accueil');
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
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Quitter'),
              ),
            ],
          ),
        );

        if (shouldQuit == true) await SystemNavigator.pop();
      },
      child: child,
    );
  }
}

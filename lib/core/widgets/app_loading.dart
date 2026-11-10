import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// The app's only start-up loading: the logo and a spinner, centred on the dark background.
///
/// The web page shows nothing before Flutter starts (no HTML loader), and every screen of the
/// start (session check, « Qui regarde ? », the home page) shows this same widget while it loads:
/// one loading that stays in place, never two or three at once (developer's request).
class AppLoading extends StatelessWidget {
  const AppLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: VxColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VxLogo(size: 40),
            SizedBox(height: 32),
            SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

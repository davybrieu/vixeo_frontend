import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';
import '../auth/session.dart';
import '../profiles/avatars.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _phoneTabs = [
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/ma-liste', 'Ma liste', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
];

const _railItems = [
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/films', 'Films', Icons.movie_outlined, Icons.movie_rounded),
  _Destination('/series', 'Séries', Icons.tv_outlined, Icons.tv_rounded),
  _Destination('/ma-liste', 'Ma liste', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
];

/// Main navigation: bottom tab bar on phones, left rail elsewhere (TV, tablet, desktop).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profile = ref.watch(sessionProvider).profile;

    if (layout.isPhone) {
      final index = location.startsWith('/profil')
          ? _phoneTabs.length
          : _phoneTabs.indexWhere((d) => location.startsWith(d.path));
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: const Color(0xF0070A08),
            indicatorColor: VxColors.accent.withValues(alpha: 0.14),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => VxText.body(
                11,
                weight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
                color: states.contains(WidgetState.selected) ? VxColors.accent : VxColors.textSecondary,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? VxColors.accent : VxColors.textSecondary,
              ),
            ),
          ),
          child: NavigationBar(
            height: 68,
            selectedIndex: index < 0 ? 0 : index,
            onDestinationSelected: (i) {
              context.go(i < _phoneTabs.length ? _phoneTabs[i].path : '/profil');
            },
            destinations: [
              for (final d in _phoneTabs)
                NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
              NavigationDestination(
                icon: ProfileAvatar(profile: profile, size: 26, radius: 7),
                label: 'Profil',
                tooltip: 'Mon profil',
              ),
            ],
          ),
        ),
      );
    }

    final railWidth = layout.isLarge ? layout.tv(120).clamp(64, 140).toDouble() : 80.0;
    final itemSize = layout.isLarge ? layout.tv(72).clamp(44, 84).toDouble() : 52.0;
    return Scaffold(
      body: Row(
        children: [
          Container(
              width: railWidth,
              color: const Color(0xE6070A08),
              padding: EdgeInsets.symmetric(vertical: layout.isLarge ? layout.tv(56) : 24),
              child: Column(
                children: [
                  VxFocusable(
                    onPressed: () => context.go('/profil'),
                    borderRadius: itemSize * 0.25,
                    onAccent: profile?.avatar == null,
                    semanticLabel: 'Mon profil (${profile?.name ?? ''})',
                    child: ProfileAvatar(profile: profile, size: itemSize * 0.78, radius: itemSize * 0.2),
                  ),
                  SizedBox(height: itemSize * 0.8),
                  for (final d in _railItems)
                    Padding(
                      padding: EdgeInsets.only(bottom: itemSize * 0.16),
                      child: _RailItem(destination: d, selected: _isSelected(d.path), size: itemSize),
                    ),
                ],
              ),
          Expanded(child: child),
        ],
      ),
    );
  }

  bool _isSelected(String path) => location == path || location.startsWith('$path/');
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.destination, required this.selected, required this.size});

  final _Destination destination;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: destination.label,
    child: VxFocusable(
      onPressed: () => context.go(destination.path),
      borderRadius: size * 0.25,
      focusScale: 1.08,
      semanticLabel: destination.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? VxColors.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: Icon(
          selected ? destination.selectedIcon : destination.icon,
          size: size * 0.45,
          color: selected ? VxColors.accent : VxColors.textSecondary,
        ),
      ),
    ),
  );
}

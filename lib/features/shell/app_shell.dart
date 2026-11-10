import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../profiles/avatars.dart';
import 'back_navigation_guard.dart';

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
  _Destination('/favoris', 'Favoris', Icons.favorite_border_rounded, Icons.favorite_rounded),
  _Destination('/avis', 'Avis', Icons.rate_review_outlined, Icons.rate_review_rounded),
];

/// Extra bottom inset so list content clears the floating pill (pill ~50 + margins).
const _phoneNavClearance = 66.0;

final _tvSidebarFocusNode = FocusNode(debugLabel: 'Navigation latérale');

const _railItems = [
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/films', 'Films', Icons.movie_outlined, Icons.movie_rounded),
  _Destination('/series', 'Séries', Icons.tv_outlined, Icons.tv_rounded),
  _Destination('/ma-liste', 'Ma liste', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
  _Destination('/favoris', 'Favoris', Icons.favorite_border_rounded, Icons.favorite_rounded),
  _Destination('/avis', 'Avis', Icons.rate_review_outlined, Icons.rate_review_rounded),
];

/// The home page was drawn once since the app started (see [AppShell.build]).
bool _homeShown = false;

/// Main navigation: bottom tab bar on phones, left rail elsewhere (TV, tablet, desktop).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profile = ref.watch(sessionProvider).profile;

    // First load of the home page after the start: the start-up loading stays alone on screen,
    // without the navigation, until the home page can be drawn. Only once: coming back to the
    // home page later shows its own loading inside the navigation.
    if (location == '/accueil' && !_homeShown) {
      final home = ref.watch(homeProvider(null));
      if (!home.hasValue && !home.hasError) {
        return BackNavigationGuard(
          location: location,
          child: const Scaffold(body: AppLoading()),
        );
      }
      _homeShown = true;
    }

    if (layout.isPhone) {
      const navigationPages = {
        '/accueil',
        '/recherche',
        '/ma-liste',
        '/favoris',
        '/avis',
        '/films',
        '/series',
        '/profil',
      };
      final showNavigation = navigationPages.contains(location);
      final index = location == '/profil' ? _phoneTabs.length : _phoneTabs.indexWhere((d) => location == d.path);
      final selectedIndex = index < 0 ? 0 : index;

      // Content fills the screen so the glass bar can blur what is behind it.
      // Scrollables that respect MediaQuery.padding get an extra bottom inset.
      final media = MediaQuery.of(context);
      final body = showNavigation
          ? MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(bottom: media.padding.bottom + _phoneNavClearance)),
              child: child,
            )
          : child;

      return BackNavigationGuard(
        location: location,
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              body,
              if (showNavigation)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PhoneNavigationBar(
                    selectedIndex: selectedIndex,
                    profile: profile,
                    onDestinationSelected: (i) {
                      context.go(i < _phoneTabs.length ? _phoneTabs[i].path : '/profil');
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final railWidth = layout.isLarge ? layout.tv(120).clamp(64, 140).toDouble() : 80.0;
    final itemSize = layout.isLarge ? layout.tv(72).clamp(44, 84).toDouble() : 52.0;
    return BackNavigationGuard(
      location: location,
      child: Scaffold(
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
                      child: _RailItem(
                        destination: d,
                        selected: _isSelected(d.path),
                        size: itemSize,
                        focusNode: d == _railItems.first ? _tvSidebarFocusNode : null,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    final current = FocusManager.instance.primaryFocus;
                    if (current != null && current.focusInDirection(TraversalDirection.left)) {
                      return KeyEventResult.handled;
                    }
                    _tvSidebarFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSelected(String path) => location == path || location.startsWith('$path/');
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.destination, required this.selected, required this.size, this.focusNode});

  final _Destination destination;
  final bool selected;
  final double size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: destination.label,
    child: VxFocusable(
      onPressed: () => context.go(destination.path),
      borderRadius: size * 0.25,
      focusScale: 1.08,
      focusNode: focusNode,
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

/// Floating glass navigation for phones — overlays content, no opaque scaffold strip.
class _PhoneNavigationBar extends StatelessWidget {
  const _PhoneNavigationBar({required this.selectedIndex, required this.profile, required this.onDestinationSelected});

  final int selectedIndex;
  final Profile? profile;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0x55070A08),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  children: [
                    for (var i = 0; i < _phoneTabs.length + 1; i++)
                      Expanded(
                        child: _PhoneNavigationItem(
                          selected: selectedIndex == i,
                          onPressed: () => onDestinationSelected(i),
                          child: i == _phoneTabs.length
                              ? ProfileAvatar(profile: profile, size: 28, radius: 15)
                              : Icon(selectedIndex == i ? _phoneTabs[i].selectedIcon : _phoneTabs[i].icon, size: 24),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneNavigationItem extends StatelessWidget {
  const _PhoneNavigationItem({required this.selected, required this.onPressed, required this.child});

  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.13) : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: selected ? VxColors.text : VxColors.textSecondary, size: 30),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

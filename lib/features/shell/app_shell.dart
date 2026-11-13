import 'dart:math' as math;
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

const _guestPhoneTabs = [
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
];

const _phoneTabs = [
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/ma-liste', 'Ma liste', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
  _Destination('/avis', 'Avis', Icons.rate_review_outlined, Icons.rate_review_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
];

/// Extra bottom inset so list content clears the floating pill (pill ~50 + margins).
const _phoneNavClearance = 66.0;

final _tvSidebarFocusNode = FocusNode(debugLabel: 'Navigation latérale');

const _guestRailItems = [
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
];

const _railItems = [
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/ma-liste', 'Ma liste', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
  _Destination('/avis', 'Avis', Icons.rate_review_outlined, Icons.rate_review_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
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
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final guest = session.isGuest;
    final phoneTabs = guest ? _guestPhoneTabs : _phoneTabs;
    final railItems = guest ? _guestRailItems : _railItems;

    // First load of the home page after the start: the start-up loading stays alone on screen,
    // without the navigation, until the home page can be drawn. Only once: coming back to the
    // home page later shows its own loading inside the navigation.
    if (location == '/accueil' && !_homeShown) {
      final home = ref.watch(homeProvider);
      if (!home.hasValue && !home.hasError) {
        return BackNavigationGuard(
          location: location,
          child: const Scaffold(body: AppLoading()),
        );
      }
      _homeShown = true;
    }

    if (layout.isPhone) {
      final navigationPages = guest
          ? {'/accueil', '/recherche', '/chaines-tv'}
          : {'/accueil', '/recherche', '/ma-liste', '/avis', '/chaines-tv', '/profil'};
      final showNavigation = navigationPages.contains(location);
      final index = location == '/profil' ? phoneTabs.length : phoneTabs.indexWhere((d) => location == d.path);
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
      final page = guest
          ? Column(
              children: [
                _GuestBanner(onSignIn: () => context.go('/connexion?redirect=${Uri.encodeComponent(location)}')),
                Expanded(child: body),
              ],
            )
          : body;

      return BackNavigationGuard(
        location: location,
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              page,
              if (showNavigation)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PhoneNavigationBar(
                    selectedIndex: selectedIndex,
                    profile: profile,
                    tabs: phoneTabs,
                    guest: guest,
                    onDestinationSelected: (i) {
                      context.go(i < phoneTabs.length ? phoneTabs[i].path : (guest ? '/connexion' : '/profil'));
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
            _Rail(
              width: railWidth,
              itemSize: itemSize,
              padding: layout.isLarge ? layout.tv(56) : 24,
              items: railItems,
              guest: guest,
              profile: profile,
              isSelected: _isSelected,
            ),
            Expanded(
              child: Column(
                children: [
                  if (guest) _GuestBanner(onSignIn: () => context.go('/connexion')),
                  Expanded(child: Focus(
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
              )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSelected(String path) => location == path || location.startsWith('$path/');
}

/// Left rail (tablet, desktop, TV): the profile, then the destinations.
///
/// On a low screen (a small tablet or a phone held sideways), the icons and margins shrink so
/// that everything stays visible; if it still doesn't fit, the rail scrolls, with a scrollbar.
class _Rail extends StatefulWidget {
  const _Rail({
    required this.width,
    required this.itemSize,
    required this.padding,
    required this.items,
    required this.guest,
    required this.profile,
    required this.isSelected,
  });

  final double width;

  /// Size of an item and vertical padding when the screen is high enough.
  final double itemSize;
  final double padding;
  final List<_Destination> items;
  final bool guest;
  final Profile? profile;
  final bool Function(String path) isSelected;

  /// Smallest item on a low screen: still easy to press.
  static const minItemSize = 40.0;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: widget.width,
    color: const Color(0xE6070A08),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Height of the content, in item sizes: the profile (0.78), a gap (0.8), then each
        // destination and the gap under it (1.16).
        final units = 1.58 + 1.16 * widget.items.length;
        var size = widget.itemSize;
        var padding = widget.padding;
        final height = constraints.maxHeight;
        if (height.isFinite && padding * 2 + size * units > height) {
          padding = math.min(padding, 12.0);
          size = ((height - padding * 2) / units).clamp(math.min(_Rail.minItemSize, size), size).toDouble();
        }

        return Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.symmetric(vertical: padding),
            child: Column(
              children: [
                if (widget.guest)
                  VxFocusable(
                    onPressed: () => context.go('/connexion'),
                    borderRadius: size * 0.25,
                    semanticLabel: 'Se connecter',
                    child: Container(
                      width: size * 0.78,
                      height: size * 0.78,
                      decoration: BoxDecoration(
                        color: VxColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(size * 0.2),
                      ),
                      child: Icon(Icons.login_rounded, size: size * 0.38, color: VxColors.accent),
                    ),
                  )
                else
                  VxFocusable(
                    onPressed: () => context.go('/profil'),
                    borderRadius: size * 0.25,
                    onAccent: widget.profile?.avatar == null,
                    semanticLabel: 'Mon profil (${widget.profile?.name ?? ''})',
                    child: ProfileAvatar(profile: widget.profile, size: size * 0.78, radius: size * 0.2),
                  ),
                SizedBox(height: size * 0.8),
                for (final d in widget.items)
                  Padding(
                    padding: EdgeInsets.only(bottom: size * 0.16),
                    child: _RailItem(
                      destination: d,
                      selected: widget.isSelected(d.path),
                      size: size,
                      focusNode: d == widget.items.first ? _tvSidebarFocusNode : null,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF17243B),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: VxColors.accent, size: 20),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Mode invité · Connectez-vous pour retrouver vos profils et vos fonctionnalités personnelles.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onSignIn, child: const Text('Se connecter')),
          ],
        ),
      ),
    ),
  );
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
  const _PhoneNavigationBar({required this.selectedIndex, required this.profile, required this.tabs, required this.guest, required this.onDestinationSelected});

  final int selectedIndex;
  final Profile? profile;
  final List<_Destination> tabs;
  final bool guest;
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
                    for (var i = 0; i < tabs.length + 1; i++)
                      Expanded(
                        child: _PhoneNavigationItem(
                          selected: selectedIndex == i,
                          onPressed: () => onDestinationSelected(i),
                          child: i == tabs.length
                              ? (guest
                                  ? const Icon(Icons.login_rounded, size: 24)
                                  : ProfileAvatar(profile: profile, size: 28, radius: 15))
                              : Icon(selectedIndex == i ? tabs[i].selectedIcon : tabs[i].icon, size: 24),
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

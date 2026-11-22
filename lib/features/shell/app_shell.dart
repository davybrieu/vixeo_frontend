import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../notifications/inbox.dart';
import '../notifications/inbox_screen.dart';
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

/// « Notifications »: with the number of unread ones (not for a child's profile).
const _notifications = _Destination(
  InboxScreen.location,
  'Notifications',
  Icons.notifications_none_rounded,
  Icons.notifications_rounded,
);

const _phoneTabs = [
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _notifications,
  _Destination('/messages', 'Messages', Icons.mail_outline_rounded, Icons.mail_rounded),
  _Destination('/profil', 'Profil', Icons.person_outline_rounded, Icons.person_rounded),
  _Destination('/parametres', 'Paramètres', Icons.settings_outlined, Icons.settings_rounded),
];

/// Extra bottom inset so list content clears the floating pill (pill ~50 + margins).
const _phoneNavClearance = 66.0;

const _guestRailItems = [
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
];

const _railItems = [
  _Destination('/accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Destination('/chaines-tv', 'Chaînes TV', Icons.live_tv_outlined, Icons.live_tv_rounded),
  _Destination('/recherche', 'Recherche', Icons.search_rounded, Icons.search_rounded),
  _notifications,
  _Destination('/messages', 'Messages', Icons.mail_outline_rounded, Icons.mail_rounded),
  _Destination('/profil', 'Profil', Icons.person_outline_rounded, Icons.person_rounded),
  _Destination('/parametres', 'Paramètres', Icons.settings_outlined, Icons.settings_rounded),
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
    // « Chaînes TV » only while live TV is shown (hidden for now: core/features.dart).
    final liveTv = ref.watch(liveTvProvider);
    final inbox = socialAvailable(session);
    final unread = inbox ? ref.watch(unreadNotificationsProvider) : 0;
    bool shown(_Destination d) => switch (d.path) {
      '/chaines-tv' => liveTv,
      InboxScreen.location => inbox,
      '/messages' => inbox,
      _ => true,
    };
    final phoneTabs = [for (final d in guest ? _guestPhoneTabs : _phoneTabs) if (shown(d)) d];
    final railItems = [for (final d in guest ? _guestRailItems : _railItems) if (shown(d)) d];
    // The badge is read again when the navigation changes page or the app comes back.
    Widget watched(Widget shell) => _UnreadWatcher(location: location, enabled: inbox, child: shell);

    // First load of the home page after the start: the start-up loading stays alone on screen,
    // without the navigation, until the home page can be drawn. Only once: coming back to the
    // home page later shows its own loading inside the navigation.
    if (location == '/accueil' && !_homeShown) {
      final home = ref.watch(homeProvider);
      if (!home.hasValue && !home.hasError) {
        return watched(
          BackNavigationGuard(
            location: location,
            child: const Scaffold(body: AppLoading()),
          ),
        );
      }
      _homeShown = true;
    }

    if (layout.isPhone) {
      final navigationPages = guest
          ? {'/accueil', '/recherche', '/chaines-tv'}
          : {'/accueil', '/chaines-tv', '/recherche', InboxScreen.location, '/messages', '/profil', '/parametres'};
      final showNavigation = navigationPages.contains(location) || location.startsWith('/messages/');
      final index = phoneTabs.indexWhere((d) => location == d.path);
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

      return watched(BackNavigationGuard(
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
                    unread: unread,
                    onDestinationSelected: (i) {
                      if (guest && i == phoneTabs.length) {
                        context.go('/connexion?redirect=${Uri.encodeComponent(location)}');
                        return;
                      }
                      context.go(phoneTabs[i].path);
                    },
                  ),
                ),
            ],
          ),
        ),
      ));
    }

    return watched(
      BackNavigationGuard(
        location: location,
        child: _LargeShell(
          layout: layout,
          items: railItems,
          guest: guest,
          profile: profile,
          unread: unread,
          isSelected: _isSelected,
          onSignIn: () => context.go('/connexion'),
          child: child,
        ),
      ),
    );
  }

  bool _isSelected(String path) => location == path || location.startsWith('$path/');
}

/// Tablet, computer, TV: the rail on the left, the pages beside it. With the arrows of a remote or
/// a keyboard (developer's request: navigation with a D-pad):
///  * Left at the left edge of a page: the rail, on the current destination (not on the item
///    that happens to be level with the focus);
///  * Right from the rail: back to the element of the page that had the focus;
///  * Up / Down stay in the rail or in the page: they never jump from one to the other.
class _LargeShell extends StatefulWidget {
  const _LargeShell({
    required this.layout,
    required this.items,
    required this.guest,
    required this.profile,
    required this.isSelected,
    required this.onSignIn,
    required this.child,
    this.unread = 0,
  });

  final Layout layout;
  final List<_Destination> items;
  final bool guest;
  final Profile? profile;
  final int unread;
  final bool Function(String path) isSelected;
  final VoidCallback onSignIn;
  final Widget child;

  @override
  State<_LargeShell> createState() => _LargeShellState();
}

class _LargeShellState extends State<_LargeShell> {
  final _railScope = FocusScopeNode(debugLabel: 'Navigation');
  final _pageScope = FocusScopeNode(debugLabel: 'Page');
  final _itemNodes = <String, FocusNode>{};

  FocusNode _itemNode(String path) => _itemNodes.putIfAbsent(path, () => FocusNode(debugLabel: 'Navigation $path'));

  @override
  void dispose() {
    _railScope.dispose();
    _pageScope.dispose();
    for (final node in _itemNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusRail() {
    final items = widget.items;
    final current = items.where((d) => widget.isSelected(d.path)).firstOrNull ?? items.firstOrNull;
    if (current != null) _itemNode(current.path).requestFocus();
  }

  /// The element of the page that had the focus last; if none, the first one of the page.
  void _focusPage() {
    FocusNode node = _pageScope;
    while (node is FocusScopeNode && node.focusedChild != null) {
      node = node.focusedChild!;
    }
    if (node is FocusScopeNode) {
      node.nextFocus();
    } else {
      node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final railWidth = layout.isLarge ? layout.tv(120).clamp(64, 140).toDouble() : 80.0;
    final itemSize = layout.isLarge ? layout.tv(72).clamp(44, 84).toDouble() : 52.0;
    return Scaffold(
      body: Row(
        children: [
          Actions(
            actions: {
              DirectionalFocusIntent: EdgeDirectionalFocusAction(outer: context, (direction) {
                if (direction != TraversalDirection.right) return false;
                _focusPage();
                return true;
              }),
            },
            child: FocusScope(
              node: _railScope,
              child: _Rail(
                width: railWidth,
                itemSize: itemSize,
                padding: layout.isLarge ? layout.tv(56) : 24,
                items: widget.items,
                guest: widget.guest,
                profile: widget.profile,
                unread: widget.unread,
                isSelected: widget.isSelected,
                itemNode: _itemNode,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (widget.guest) _GuestBanner(onSignIn: widget.onSignIn),
                Expanded(
                  child: Actions(
                    actions: {
                      DirectionalFocusIntent: EdgeDirectionalFocusAction(outer: context, (direction) {
                        if (direction != TraversalDirection.left) return false;
                        _focusRail();
                        return true;
                      }),
                    },
                    child: FocusScope(node: _pageScope, child: widget.child),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
    required this.itemNode,
    this.unread = 0,
  });

  final double width;

  /// Size of an item and vertical padding when the screen is high enough.
  final double itemSize;
  final double padding;
  final List<_Destination> items;
  final bool guest;
  final Profile? profile;
  final bool Function(String path) isSelected;

  /// Unread notifications: the badge of « Notifications ».
  final int unread;

  /// The focus node of a destination (Left from a page focuses the current one).
  final FocusNode Function(String path) itemNode;

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
        final units = 1.33 + 1.08 * widget.items.length;
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
                SizedBox(height: size * 0.55),
                for (final d in widget.items)
                  Padding(
                    padding: EdgeInsets.only(bottom: size * 0.08),
                    child: _RailItem(
                      destination: d,
                      selected: widget.isSelected(d.path),
                      size: size,
                      focusNode: widget.itemNode(d.path),
                      badge: d.path == InboxScreen.location ? widget.unread : 0,
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
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.size,
    this.focusNode,
    this.badge = 0,
  });

  final _Destination destination;
  final bool selected;
  final double size;
  final FocusNode? focusNode;

  /// A number on the icon (unread notifications); none at 0.
  final int badge;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: destination.label,
    child: VxFocusable(
      onPressed: () => context.go(destination.path),
      borderRadius: size * 0.25,
      focusScale: 1.08,
      focusNode: focusNode,
      semanticLabel: badge > 0 ? '${destination.label}, ${unreadLabel(badge)}' : destination.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? VxColors.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: Center(
          child: NavigationBadge(
            count: badge,
            size: size * 0.3,
            child: Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: size * 0.45,
              color: selected ? VxColors.accent : VxColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Floating glass navigation for phones — overlays content, no opaque scaffold strip.
class _PhoneNavigationBar extends StatelessWidget {
  const _PhoneNavigationBar({
    required this.selectedIndex,
    required this.profile,
    required this.tabs,
    required this.guest,
    required this.onDestinationSelected,
    this.unread = 0,
  });

  final int selectedIndex;
  final Profile? profile;
  final List<_Destination> tabs;
  final bool guest;
  final ValueChanged<int> onDestinationSelected;

  /// Unread notifications: the badge of « Notifications ».
  final int unread;

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
                    for (var i = 0; i < tabs.length + (guest ? 1 : 0); i++)
                      Expanded(
                        child: _PhoneNavigationItem(
                          selected: selectedIndex == i,
                          onPressed: () => onDestinationSelected(i),
                          label: i == tabs.length
                              ? 'Se connecter'
                              : tabs[i].path == InboxScreen.location && unread > 0
                                  ? '${tabs[i].label}, ${unreadLabel(unread)}'
                                  : tabs[i].label,
                          child: i == tabs.length
                              ? const Icon(Icons.login_rounded, size: 24)
                              : tabs[i].path == '/profil'
                                  ? ProfileAvatar(profile: profile, size: 28, radius: 15)
                                  : NavigationBadge(
                                      count: tabs[i].path == InboxScreen.location ? unread : 0,
                                      size: 16,
                                      child: Icon(selectedIndex == i ? tabs[i].selectedIcon : tabs[i].icon, size: 24),
                                    ),
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
  const _PhoneNavigationItem({required this.selected, required this.onPressed, required this.child, this.label});

  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  /// Read by screen readers.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      // One node per tab for screen readers: its name (and the unread notifications), pressable.
      child: Semantics(
        container: true,
        label: label,
        button: true,
        selected: selected,
        onTap: onPressed,
        child: ExcludeSemantics(
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
        ),
      ),
    );
  }
}

/// "1 notification non lue", "3 notifications non lues".
String unreadLabel(int count) => count > 1 ? '$count notifications non lues' : '$count notification non lue';

/// A number in a small round badge, at the top right of a navigation icon ("9+" above 9); just the
/// icon at 0.
class NavigationBadge extends StatelessWidget {
  const NavigationBadge({super.key, required this.count, required this.size, required this.child});

  final int count;

  /// Height of the badge.
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -size * 0.35,
          right: -size * 0.55,
          child: ExcludeSemantics(
            child: Container(
              constraints: BoxConstraints(minWidth: size, minHeight: size),
              padding: EdgeInsets.symmetric(horizontal: size * 0.25),
              decoration: BoxDecoration(
                color: VxColors.accent,
                borderRadius: BorderRadius.circular(size / 2),
                border: Border.all(color: VxColors.background, width: size * 0.1),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 9 ? '9+' : '$count',
                textScaler: TextScaler.noScaling,
                style: VxText.body(size * 0.62, weight: FontWeight.w700, color: VxColors.onAccent, height: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reads the number of unread notifications again (the badge): on arrival, when the page changes
/// (30 s at most between two readings) and when the app comes back to the foreground.
class _UnreadWatcher extends ConsumerStatefulWidget {
  const _UnreadWatcher({required this.location, required this.enabled, required this.child});

  final String location;
  final bool enabled;
  final Widget child;

  @override
  ConsumerState<_UnreadWatcher> createState() => _UnreadWatcherState();
}

class _UnreadWatcherState extends ConsumerState<_UnreadWatcher> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => _refresh(force: true));
    _refresh();
  }

  @override
  void didUpdateWidget(_UnreadWatcher old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location || old.enabled != widget.enabled) _refresh(force: !old.enabled);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// After the frame: the badge isn't changed while the pages are built.
  void _refresh({bool force = false}) {
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) ref.read(unreadNotificationsProvider.notifier).refresh(force: force);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

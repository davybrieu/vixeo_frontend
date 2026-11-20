import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../library/library.dart';
import '../ratings/ratings.dart';
import 'settings_rows.dart';

/// « Mémoriser le dernier profil » (this device): the last profile chosen opens at launch, unless
/// it has a PIN. On when never set (the app's behaviour before the setting existed).
final rememberProfileProvider = AsyncNotifierProvider<RememberProfile, bool>(RememberProfile.new);

class RememberProfile extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      return await ref.read(sessionStorageProvider).readRememberProfile();
    } catch (_) {
      return true;
    }
  }

  Future<void> set(bool value) async {
    state = AsyncData(value);
    try {
      await ref.read(sessionStorageProvider).writeRememberProfile(value);
    } catch (_) {
      // Not kept (private browsing…): for this launch only.
    }
  }
}

/// Empties the images kept on this device (posters, backdrops, logos: the disk cache of the
/// network images). Replaced in tests.
final imageDiskCacheProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await DefaultCacheManager().emptyCache();
  },
);

/// « Avancé » (Paramètres): startup and cache of this device. Developer's request, like other
/// media centers (without their crash reports).
class AdvancedSettingsScreen extends ConsumerStatefulWidget {
  const AdvancedSettingsScreen({super.key});

  static const location = '/profil/avance';

  @override
  ConsumerState<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends ConsumerState<AdvancedSettingsScreen> {
  bool _clearing = false;

  Future<void> _remember(bool value) async {
    await ref.read(rememberProfileProvider.notifier).set(value);
    if (!mounted) return;
    showVxSnack(
      context,
      value ? 'Le dernier profil s’ouvrira au lancement' : '« Qui regarde ? » s’affichera au lancement',
      icon: Icons.person_outline_rounded,
    );
  }

  /// Images, titles and ratings already read and the profile's « Continuer à regarder » /
  /// « Ma liste »: read again from the API when shown.
  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await ref.read(imageDiskCacheProvider)();
    } catch (_) {
      // Files already gone or in use: what could be removed is.
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    // Ratings of the other sites (MDBList), on the device too.
    ref.read(ratingsLoaderProvider).clear();
    ref
      ..invalidate(titleRatingsProvider)
      ..invalidate(titlesRatingsProvider)
      ..invalidate(homeProvider)
      ..invalidate(titleProvider)
      ..invalidate(titlesByIdProvider)
      ..invalidate(seasonProvider)
      ..invalidate(libraryProvider);
    if (!mounted) return;
    setState(() => _clearing = false);
    showVxSnack(context, 'Cache vidé', icon: Icons.cleaning_services_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    // Applies at the next launch: the session stays as it is.
    final remember = ref.watch(rememberProfileProvider).value ?? true;

    return InfoPage(
      title: 'Avancé',
      fallback: '/parametres',
      children: [
        SettingsSection(
          'Démarrage',
          scale: s,
          children: [
            SettingsSwitchRow(
              label: 'Mémoriser le dernier profil',
              detail: 'Ouvrir le dernier profil choisi au lancement.',
              value: remember,
              autofocus: true,
              onChanged: _remember,
            ),
          ],
        ),
        SettingsSection(
          'Cache',
          scale: s,
          last: true,
          children: [
            SettingsActionRow(
              icon: Icons.cleaning_services_outlined,
              label: 'Vider le cache',
              detail: 'Affiches, logos, notes et informations des titres, « Continuer à regarder » compris.',
              busy: _clearing,
              onPressed: _clearCache,
            ),
          ],
        ),
      ],
    );
  }
}

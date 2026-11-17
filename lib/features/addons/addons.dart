/// Plug-ins in the Stremio add-on format (API: `vixeo_backend/docs/plugins.md`).
///
/// The app only talks to the Vixeo API: it lists, installs, orders and removes the account's
/// plug-ins, and shows what the API makes of them (rows of the home, providers of the sources
/// panel). It never calls a plug-in itself.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/models.dart';

/// A plug-in of the account, as `GET /addons` gives it.
@immutable
class AddonInfo {
  const AddonInfo({
    required this.id,
    required this.name,
    this.description,
    required this.version,
    this.logoUrl,
    this.host,
    this.resources = const [],
    this.types = const [],
    this.catalogs = 0,
    this.enabled = true,
    this.builtIn = false,
    this.shared = false,
    this.adult = false,
    this.manifestUrl,
  });

  factory AddonInfo.fromJson(Map<String, dynamic> json) => AddonInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    version: json['version'] as String? ?? '',
    logoUrl: json['logo_url'] as String?,
    host: json['host'] as String?,
    resources: [for (final r in json['resources'] as List? ?? const []) r.toString()],
    types: [for (final t in json['types'] as List? ?? const []) t.toString()],
    catalogs: json['catalogs'] as int? ?? 0,
    enabled: json['enabled'] as bool? ?? true,
    builtIn: json['built_in'] as bool? ?? false,
    shared: json['shared'] as bool? ?? false,
    adult: json['adult'] as bool? ?? false,
    manifestUrl: json['manifest_url'] as String?,
  );

  /// "vixeo" for the Vixeo catalog, otherwise the plug-in's number.
  final String id;
  final String name;
  final String? description;
  final String version;
  final String? logoUrl;

  /// Host of its address ("addon.example.com"); the address itself never comes back.
  final String? host;

  /// "catalog", "meta", "stream", "subtitles".
  final List<String> resources;

  /// "movie", "tv".
  final List<String> types;

  /// Catalogs shown as rows of the home.
  final int catalogs;
  final bool enabled;

  /// The Vixeo catalog: cannot be removed (it can be turned off).
  final bool builtIn;

  /// Installed on the server for every account: the account can only turn it off.
  final bool shared;
  final bool adult;

  /// The Stremio address of the Vixeo catalog (to add it to another app); null for the others.
  final String? manifestUrl;

  /// The account's own plug-in: it can move it and remove it. Every plug-in, this one or not, can
  /// be turned off for the account.
  bool get editable => !builtIn && !shared;

  bool get hasStreams => resources.contains('stream');
  bool get hasCatalogs => catalogs > 0;
}

class AddonsRepository {
  AddonsRepository(this._api);

  final ApiClient _api;

  Future<List<AddonInfo>> list() async {
    final data = (await _api.get('/addons'))['data'];
    return data is List ? data.whereType<Map<String, dynamic>>().map(AddonInfo.fromJson).toList() : const [];
  }

  /// Installs a plug-in from the address of its manifest. Throws an ApiException whose
  /// `field('url')` says why it was refused (in French).
  Future<AddonInfo> install(String url) async =>
      AddonInfo.fromJson((await _api.post('/addons', body: {'url': url}))['data'] as Map<String, dynamic>);

  /// On or off for the account: its own plug-ins, those of every account, the Vixeo catalog ("vixeo").
  Future<void> setEnabled(String id, {required bool enabled}) => _api.patch('/addons/$id', body: {'enabled': enabled});

  /// The account's own plug-ins, first first.
  Future<void> reorder(List<String> ids) => _api.put('/addons/order', body: {'ids': ids});

  Future<void> remove(String id) => _api.delete('/addons/$id');

  /// Rows of the home from the plug-ins' catalogs, shown after the home's own rows.
  Future<List<Section>> sections() async {
    final data = (await _api.get('/catalog/addons/sections'))['sections'];
    return data is List ? data.whereType<Map<String, dynamic>>().map(Section.fromJson).toList() : const [];
  }
}

final addonsRepositoryProvider = Provider<AddonsRepository>((ref) => AddonsRepository(ref.read(apiClientProvider)));

/// The account's plug-ins (« Paramètres » → « Plug-ins »).
final addonsProvider = FutureProvider.autoDispose<List<AddonInfo>>((ref) {
  ref.watch(sessionProvider.select((s) => s.user?.id));
  return ref.read(addonsRepositoryProvider).list();
});

/// Rows of the home from the plug-ins. Never an error: a plug-in that fails, or an API that
/// does not know plug-ins yet, simply adds no row (the home stays as it is).
final addonSectionsProvider = FutureProvider.autoDispose<List<Section>>((ref) async {
  // Another account or profile: other plug-ins, another age limit.
  ref.watch(sessionProvider.select((s) => (s.user?.id, s.profile?.id)));
  try {
    return await ref.read(addonsRepositoryProvider).sections();
  } catch (_) {
    return const [];
  }
});

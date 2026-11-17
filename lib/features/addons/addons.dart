/// Plug-ins in the Stremio add-on format (API: `vixeo_backend/docs/plugins.md`), for **sources
/// only**: each one that serves streams of movies or series is a provider of the sources panel.
/// The catalog never comes from a plug-in: it stays TMDb's, as the API gives it.
///
/// The app only talks to the Vixeo API: it lists, installs, orders and removes the account's
/// plug-ins. It never calls a plug-in itself.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';

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
    this.streams,
    this.enabled = true,
    this.shared = false,
    this.adult = false,
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
    streams: json['streams'] as bool?,
    enabled: json['enabled'] as bool? ?? true,
    shared: json['shared'] as bool? ?? false,
    adult: json['adult'] as bool? ?? false,
  );

  /// The plug-in's number.
  final String id;
  final String name;
  final String? description;
  final String version;
  final String? logoUrl;

  /// Host of its address ("addon.example.com"); the address itself never comes back.
  final String? host;

  /// "catalog", "meta", "stream", "subtitles" (Vixeo only uses "stream").
  final List<String> resources;

  /// "movie", "tv".
  final List<String> types;

  /// `streams` of the API: whether it gives sources of movies or TV shows. Null from an older API.
  final bool? streams;
  final bool enabled;

  /// Installed on the server for every account: the account cannot change it.
  final bool shared;
  final bool adult;

  /// The account's own plug-in: it can turn it off, move it and remove it.
  bool get editable => !shared;

  /// Whether it gives sources. A plug-in installed when plug-ins could also add catalogs may not:
  /// it does nothing any more, and can be removed.
  bool get hasStreams => streams ?? resources.contains('stream');
}

class AddonsRepository {
  AddonsRepository(this._api);

  final ApiClient _api;

  Future<List<AddonInfo>> list() async {
    final data = (await _api.get('/addons'))['data'];
    if (data is! List) return const [];
    // An older API also listed the Vixeo catalog (`built_in`), which is no plug-in any more.
    return [
      for (final json in data.whereType<Map<String, dynamic>>())
        if (json['built_in'] != true) AddonInfo.fromJson(json),
    ];
  }

  /// Installs a plug-in from the address of its manifest. Throws an ApiException whose
  /// `field('url')` says why it was refused (in French).
  Future<AddonInfo> install(String url) async =>
      AddonInfo.fromJson((await _api.post('/addons', body: {'url': url}))['data'] as Map<String, dynamic>);

  Future<void> setEnabled(String id, {required bool enabled}) => _api.patch('/addons/$id', body: {'enabled': enabled});

  /// The account's own plug-ins, first first.
  Future<void> reorder(List<String> ids) => _api.put('/addons/order', body: {'ids': ids});

  Future<void> remove(String id) => _api.delete('/addons/$id');
}

final addonsRepositoryProvider = Provider<AddonsRepository>((ref) => AddonsRepository(ref.read(apiClientProvider)));

/// The account's plug-ins (« Paramètres » → « Plug-ins »).
final addonsProvider = FutureProvider.autoDispose<List<AddonInfo>>((ref) {
  ref.watch(sessionProvider.select((s) => s.user?.id));
  return ref.read(addonsRepositoryProvider).list();
});

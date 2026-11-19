/// The data of the plug-in system: repositories of JavaScript scrapers (`docs/scrapers.md`).
///
/// A **repository** is a `manifest.json` somebody hosts; it lists **scrapers**, JavaScript files
/// that turn a TMDb id into stream links. Execution mode (device or server) is declared in the
/// manifest, not configurable per scraper. Nothing here runs code or touches the network.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../catalog/models.dart';

/// Something the person can be told, in French (a bad address, a scraper that failed…).
class ScraperException implements Exception {
  const ScraperException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where a repository's scrapers run (declared in the manifest).
enum ScraperMode {
  /// On this device: QuickJS on Android / iOS, a sandboxed iframe in the browser.
  device('device', 'Appareil'),

  /// On the Vixeo server (`POST /scrapers/run`).
  server('server', 'Serveur');

  const ScraperMode(this.storageName, this.label);

  final String storageName;
  final String label;

  static ScraperMode parse(Object? value) => value == 'server' ? server : device;
}

/// The entries of [value] when it is a map, none otherwise.
Iterable<MapEntry<dynamic, dynamic>> _entries(Object? value) =>
    value is Map ? value.entries : const <MapEntry<dynamic, dynamic>>[];

/// What a scraper's `id` may look like (also the key of its settings).
final _idPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

/// One scraper as the repository's manifest lists it.
@immutable
class ScraperEntry {
  const ScraperEntry({
    required this.id,
    required this.name,
    required this.filename,
    this.description,
    this.version = '',
    this.types = const {'movie', 'tv'},
    this.logo,
  });

  /// Null for an entry that cannot be used (no id, no file…): it is left out, not an error.
  static ScraperEntry? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    final filename = _text(json['filename']) ?? _text(json['file']);
    if (id == null || !_idPattern.hasMatch(id) || filename == null) return null;
    final types = {
      for (final t in json['supportedTypes'] is List ? json['supportedTypes'] as List : const [])
        if (t == 'movie' || t == 'tv') t as String,
    };
    return ScraperEntry(
      id: id,
      name: _text(json['name']) ?? id,
      filename: filename,
      description: _text(json['description']),
      version: _text(json['version']) ?? '',
      types: types.isEmpty ? const {'movie', 'tv'} : types,
      logo: _text(json['logo']) ?? _text(json['logo_url']),
    );
  }

  final String id;
  final String name;

  /// Relative to the manifest's address, or a full `https://` address.
  final String filename;
  final String? description;
  final String version;

  /// "movie", "tv".
  final Set<String> types;
  final String? logo;
}

/// A repository's `manifest.json`, read.
@immutable
class RepositoryManifest {
  const RepositoryManifest({
    required this.name,
    this.description,
    this.version,
    required this.scrapers,
    this.execution = ScraperMode.device,
  });

  /// Reads a manifest (the list may be called `scrapers` or `providers`, or be the whole file).
  /// Throws a [ScraperException] when it is not a manifest or has nothing usable.
  factory RepositoryManifest.parse(Object? json, {required String fallbackName}) {
    final Object? list = json is List ? json : (json is Map ? (json['scrapers'] ?? json['providers']) : null);
    if (list is! List) throw const ScraperException("Ce n'est pas le manifeste d'un dépôt de plug-ins.");
    final seen = <String>{};
    final scrapers = [
      for (final item in list)
        if (ScraperEntry.tryParse(item) case final entry? when seen.add(entry.id)) entry,
    ];
    if (scrapers.isEmpty) throw const ScraperException('Ce dépôt ne contient aucun plug-in utilisable.');
    final meta = json is Map ? json : const <dynamic, dynamic>{};
    return RepositoryManifest(
      name: _text(meta['name']) ?? fallbackName,
      description: _text(meta['description']),
      version: _text(meta['version']),
      scrapers: scrapers,
      execution: ScraperMode.parse(meta['execution']),
    );
  }

  final String name;
  final String? description;
  final String? version;
  final List<ScraperEntry> scrapers;
  final ScraperMode execution;
}

/// An installed scraper: what the manifest says. No individual enable/mode (controlled at repo level).
@immutable
class ScraperInfo {
  const ScraperInfo({
    required this.id,
    required this.repositoryId,
    required this.name,
    required this.filename,
    this.description,
    this.version = '',
    this.types = const {'movie', 'tv'},
    this.logo,
  });

  factory ScraperInfo.fromEntry(String repositoryId, ScraperEntry entry) => ScraperInfo(
    id: entry.id,
    repositoryId: repositoryId,
    name: entry.name,
    filename: entry.filename,
    description: entry.description,
    version: entry.version,
    types: entry.types,
    logo: entry.logo,
  );

  static ScraperInfo? tryFromJson(String repositoryId, Object? json) {
    final entry = ScraperEntry.tryParse(json);
    if (entry == null) return null;
    return ScraperInfo.fromEntry(repositoryId, entry);
  }

  final String id;
  final String repositoryId;
  final String name;
  final String filename;
  final String? description;
  final String version;
  final Set<String> types;
  final String? logo;

  /// Unique among every repository: the key of its settings and of its provider id.
  String get key => '$repositoryId:$id';

  /// The id the player's sources panel knows it by.
  String get providerId => 'scraper:$key';

  bool supports(MediaType type) => types.contains(type == MediaType.movie ? 'movie' : 'tv');

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'filename': filename,
    if (description != null) 'description': description,
    'version': version,
    'supportedTypes': types.toList()..sort(),
    if (logo != null) 'logo': logo,
  };
}

/// An installed repository and its scrapers, in the order the person chose.
@immutable
class ScraperRepo {
  const ScraperRepo({
    required this.id,
    required this.url,
    required this.name,
    this.description,
    this.version,
    required this.scrapers,
    this.mode = ScraperMode.device,
  });

  /// Reads a repository from its manifest (first install).
  factory ScraperRepo.fromManifest(String url, RepositoryManifest manifest) {
    final id = idFor(url);
    return ScraperRepo(
      id: id,
      url: url,
      name: manifest.name,
      description: manifest.description,
      version: manifest.version,
      scrapers: [for (final entry in manifest.scrapers) ScraperInfo.fromEntry(id, entry)],
      mode: manifest.execution,
    );
  }

  static ScraperRepo? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final url = _text(json['url']);
    if (url == null) return null;
    final id = idFor(url);
    return ScraperRepo(
      id: id,
      url: url,
      name: _text(json['name']) ?? hostOf(url),
      description: _text(json['description']),
      version: _text(json['version']),
      scrapers: [
        for (final item in json['scrapers'] is List ? json['scrapers'] as List : const [])
          ?ScraperInfo.tryFromJson(id, item),
      ],
      mode: ScraperMode.parse(json['mode']),
    );
  }

  /// Reads what [encodeList] wrote; anything else is an empty list.
  static List<ScraperRepo> decodeList(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final json = jsonDecode(text);
      if (json is! List) return const [];
      return [
        for (final item in json)
          ?tryFromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  static String encodeList(List<ScraperRepo> repos) => jsonEncode([for (final r in repos) r.toJson()]);

  /// A short stable id from the address (the address itself is long and has symbols).
  static String idFor(String url) => sha1.convert(utf8.encode(url)).toString().substring(0, 8);

  static String hostOf(String url) => Uri.tryParse(url)?.host ?? url;

  /// The address the person typed, as the address of a manifest. Throws a [ScraperException] when
  /// it cannot be one: only `https://` is accepted, and an address that ends at a folder gets
  /// `manifest.json`.
  static String normalizeUrl(String input) {
    final text = input.trim();
    if (text.isEmpty) throw const ScraperException("Collez l'adresse du dépôt.");
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ScraperException('Cette adresse n’est pas valide.');
    }
    if (uri.scheme != 'https') throw const ScraperException('Seules les adresses https:// sont acceptées.');
    if (uri.userInfo.isNotEmpty) throw const ScraperException('Cette adresse n’est pas valide.');
    final withFile = uri.path.isEmpty || uri.path.endsWith('/') ? uri.resolve('manifest.json') : uri;
    return withFile.removeFragment().toString();
  }

  final String id;
  final String url;
  final String name;
  final String? description;
  final String? version;
  final List<ScraperInfo> scrapers;
  final ScraperMode mode;

  String get host => hostOf(url);

  /// The address of one scraper's file.
  Uri fileOf(ScraperInfo scraper) => Uri.parse(url).resolve(scraper.filename);

  ScraperRepo copyWith({
    List<ScraperInfo>? scrapers,
    String? name,
    String? description,
    String? version,
    ScraperMode? mode,
  }) => ScraperRepo(
    id: id,
    url: url,
    name: name ?? this.name,
    description: description ?? this.description,
    version: version ?? this.version,
    scrapers: scrapers ?? this.scrapers,
    mode: mode ?? this.mode,
  );

  /// This repository after its manifest was read again: the scrapers that are still listed keep
  /// their place; new ones come last; the ones no longer listed are dropped. Mode comes from the
  /// new manifest.
  ScraperRepo updatedWith(RepositoryManifest manifest) {
    final entries = {for (final entry in manifest.scrapers) entry.id: entry};
    final kept = [
      for (final old in scrapers)
        if (entries.remove(old.id) case final entry?)
          ScraperInfo.fromEntry(id, entry),
    ];
    return ScraperRepo(
      id: id,
      url: url,
      name: manifest.name,
      description: manifest.description,
      version: manifest.version,
      scrapers: [...kept, for (final entry in entries.values) ScraperInfo.fromEntry(id, entry)],
      mode: manifest.execution,
    );
  }

  Map<String, Object?> toJson() => {
    'url': url,
    'name': name,
    if (description != null) 'description': description,
    if (version != null) 'version': version,
    'mode': mode.storageName,
    'scrapers': [for (final s in scrapers) s.toJson()],
  };
}

/// What a scraper is asked for.
@immutable
class ScraperParams {
  const ScraperParams({required this.tmdbId, required this.mediaType, this.season, this.episode});

  /// A text, like Nuvio ("550").
  final String tmdbId;

  /// "movie" or "tv".
  final String mediaType;
  final int? season;
  final int? episode;

  Map<String, Object?> toJson() => {'tmdbId': tmdbId, 'mediaType': mediaType, 'season': season, 'episode': episode};
}

/// A stream link a scraper found (`docs/scrapers.md` §3).
@immutable
class ScraperStream {
  const ScraperStream({required this.url, this.name, this.title, this.quality, this.size, this.headers = const {}});

  /// The most streams kept from one scraper.
  static const maxPerScraper = 50;

  /// Null for something that is not a playable link (no address, a `javascript:` address…).
  static ScraperStream? tryParse(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
    String? number(Object? v) => v is num ? '$v' : _text(v);
    return ScraperStream(
      url: url.trim(),
      name: _text(json['name']) ?? _text(json['title']) ?? _text(json['provider']),
      title: _text(json['title']),
      quality: number(json['quality']),
      size: number(json['size']),
      headers: {
        for (final e in _entries(json['headers']))
          if (e.key is String && (e.value is String || e.value is num)) e.key as String: '${e.value}',
      },
    );
  }

  /// The valid links of a scraper's answer ([maxPerScraper] at most).
  static List<ScraperStream> parseList(Object? json, {int max = maxPerScraper}) {
    if (json is! List) return const [];
    final out = <ScraperStream>[];
    for (final item in json) {
      final stream = tryParse(item);
      if (stream != null) out.add(stream);
      if (out.length >= max) break;
    }
    return out;
  }

  final String url;
  final String? name;
  final String? title;
  final String? quality;
  final String? size;

  /// What the player must send with the request (Referer, Origin…).
  final Map<String, String> headers;

  /// "m3u8" or "mp4" when the address says so, else null (the player finds out).
  String? get streamType {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    if (path.endsWith('.m3u8')) return 'm3u8';
    if (path.endsWith('.mp4')) return 'mp4';
    return null;
  }

  /// What the sources panel writes: « Serveur 1 · 1080p · 1.2 GB ».
  String label(String fallback) => [name ?? fallback, ?quality, ?size].join(' · ');
}

/// A scraper and its repository, found from a provider id.
typedef ScraperMatch = ({ScraperRepo repo, ScraperInfo scraper});

/// The scraper `scraper:{repository}:{id}` names, among [repos]; null when it is gone.
ScraperMatch? findScraper(List<ScraperRepo> repos, String providerId) {
  if (!providerId.startsWith('scraper:')) return null;
  for (final repo in repos) {
    for (final scraper in repo.scrapers) {
      if (scraper.providerId == providerId) return (repo: repo, scraper: scraper);
    }
  }
  return null;
}

/// The data of the plug-in system: repositories of JavaScript scrapers (`docs/scrapers.md`).
///
/// A **repository** is a `manifest.json` somebody hosts; it lists **scrapers**, JavaScript files
/// that turn a TMDb id into stream links. They always run on the device (Android, iOS, Windows).
/// Nothing here runs code or touches the network.
///
/// The formats are Nuvio's (its app reads them the same way): a repository made for Nuvio, such as
/// gowaru-nuvio-providers, installs and gives its streams as it is.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../catalog/models.dart';
import 'scraper_guard.dart';

/// Something the person can be told, in French (a bad address, a scraper that failed…).
class ScraperException implements Exception {
  const ScraperException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The platform names a Nuvio manifest uses in `supportedPlatforms` / `disabledPlatforms`
/// ("android", "ios"; "windows" for the Windows app, which Nuvio does not have).
String get currentScraperPlatform {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    final other => other.name.toLowerCase(),
  };
}

/// The entries of [value] when it is a map, none otherwise.
Iterable<MapEntry<dynamic, dynamic>> _entries(Object? value) =>
    value is Map ? value.entries : const <MapEntry<dynamic, dynamic>>[];

/// What a scraper's `id` may look like (also the key of its settings).
final _idPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// A text worth keeping. As in Nuvio, a text that contains "[object" (a JavaScript object turned
/// into text by mistake) is none.
String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty && !value.contains('[object') ? value.trim() : null;

/// The lower-case texts of a list (a manifest's list of platforms…), none for anything else.
Set<String> _names(Object? value) => {
  for (final item in value is List ? value : const []) ?_text(item)?.toLowerCase(),
};

/// Nuvio's names of the types: "series", "show" and "other" are series ("tv").
String? _type(Object? value) => switch (value is String ? value.toLowerCase() : null) {
  'movie' => 'movie',
  'tv' || 'series' || 'show' || 'other' => 'tv',
  _ => null,
};

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
      for (final t in json['supportedTypes'] is List ? json['supportedTypes'] as List : const []) ?_type(t),
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
  });

  /// Reads a manifest (the list may be called `scrapers` or `providers`, or be the whole file).
  /// Throws a [ScraperException] when it is not a manifest or has nothing usable.
  ///
  /// As Nuvio does, a scraper its author turned off (`"enabled": false`: a site that is down…) is
  /// left out, and so is one whose `supportedPlatforms` / `disabledPlatforms` exclude [platform]
  /// (this device's, [currentScraperPlatform], by default).
  factory RepositoryManifest.parse(Object? json, {required String fallbackName, String? platform}) {
    final Object? list = json is List ? json : (json is Map ? (json['scrapers'] ?? json['providers']) : null);
    if (list is! List) throw const ScraperException("Ce n'est pas le manifeste d'un dépôt de plug-ins.");
    final here = platform ?? currentScraperPlatform;
    final seen = <String>{};
    final scrapers = [
      for (final item in list)
        if (_usable(item, here))
          if (ScraperEntry.tryParse(item) case final entry? when seen.add(entry.id)) entry,
    ];
    if (scrapers.isEmpty) throw const ScraperException('Ce dépôt ne contient aucun plug-in utilisable.');
    final meta = json is Map ? json : const <dynamic, dynamic>{};
    return RepositoryManifest(
      name: _text(meta['name']) ?? fallbackName,
      description: _text(meta['description']),
      version: _text(meta['version']),
      scrapers: scrapers,
    );
  }

  final String name;
  final String? description;
  final String? version;
  final List<ScraperEntry> scrapers;

  /// Whether the author lets this entry run on [platform] (Nuvio's `enabled`,
  /// `supportedPlatforms`, `disabledPlatforms`).
  static bool _usable(Object? item, String platform) {
    if (item is! Map) return false;
    if (item['enabled'] == false) return false;
    final supported = _names(item['supportedPlatforms']);
    if (supported.isNotEmpty && !supported.contains(platform)) return false;
    return !_names(item['disabledPlatforms']).contains(platform);
  }
}

/// An installed scraper: what the manifest says. No individual switch (controlled at repo level).
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

/// An installed repository (an add-on). It is the unit the person manages: turned on or off and
/// moved as a whole in « Plug-ins », where its scrapers are not listed. Its scrapers keep the
/// manifest's order.
@immutable
class ScraperRepo {
  const ScraperRepo({
    required this.id,
    required this.url,
    required this.name,
    this.description,
    this.version,
    required this.scrapers,
    this.enabled = true,
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
      // Older data has no flag: the repository was in use.
      enabled: json['enabled'] != false,
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

  /// The address the person typed, as the address of a manifest, the way Nuvio reads it: the
  /// address of a folder gets `/manifest.json` (with or without its last `/`), `https://` is added
  /// when it is missing and `http://` becomes `https://`; a GitHub page of the repository
  /// (`https://github.com/owner/repo`, `…/tree/branch/folder`, `…/blob/branch/file.json`) becomes
  /// the address of its raw file. Throws a [ScraperException] when it cannot be an address.
  static String normalizeUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) throw const ScraperException("Collez l'adresse du dépôt.");
    if (!text.contains('://')) text = 'https://$text';
    final parsed = Uri.tryParse(ScraperGuard.upgrade(text));
    if (parsed == null || parsed.host.isEmpty || !parsed.host.contains('.')) {
      throw const ScraperException('Cette adresse n’est pas valide.');
    }
    if (parsed.scheme != 'https') throw const ScraperException('Seules les adresses https:// sont acceptées.');
    if (parsed.userInfo.isNotEmpty) throw const ScraperException('Cette adresse n’est pas valide.');
    var uri = _fromGitHub(parsed.removeFragment());
    final segments = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
    if (segments.isEmpty || !segments.last.toLowerCase().endsWith('.json')) {
      uri = uri.replace(pathSegments: [...segments, 'manifest.json']);
    }
    return uri.toString();
  }

  /// `https://github.com/owner/repo[/tree|blob/branch/path]` → the same file on
  /// raw.githubusercontent.com (`HEAD` for the default branch). Any other address is kept.
  static Uri _fromGitHub(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'github.com' && host != 'www.github.com') return uri;
    final parts = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
    if (parts.length < 2) return uri;
    final owner = parts[0];
    final repo = parts[1].endsWith('.git') ? parts[1].substring(0, parts[1].length - 4) : parts[1];
    final hasRef = parts.length >= 4 && (parts[2] == 'tree' || parts[2] == 'blob');
    return Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [owner, repo, if (hasRef) ...parts.sublist(3) else 'HEAD'],
    );
  }

  final String id;
  final String url;
  final String name;
  final String? description;
  final String? version;
  final List<ScraperInfo> scrapers;

  /// Off: still installed, but its scrapers give no sources (« Plug-ins »).
  final bool enabled;

  String get host => hostOf(url);

  /// The address of one scraper's file: as in Nuvio, a `filename` is read from the manifest's folder
  /// even when it starts with `/`; a full address stays (in https).
  Uri fileOf(ScraperInfo scraper) {
    final file = ScraperGuard.upgrade(scraper.filename);
    if (file.startsWith('https://')) return Uri.parse(file);
    var relative = file;
    while (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    return Uri.parse(url).resolve(relative);
  }

  ScraperRepo copyWith({
    List<ScraperInfo>? scrapers,
    String? name,
    String? description,
    String? version,
    bool? enabled,
  }) => ScraperRepo(
    id: id,
    url: url,
    name: name ?? this.name,
    description: description ?? this.description,
    version: version ?? this.version,
    scrapers: scrapers ?? this.scrapers,
    enabled: enabled ?? this.enabled,
  );

  /// This repository after its manifest was read again: its scrapers are the manifest's, in the
  /// manifest's order (the add-on decides, the person does not see them). Only
  /// what the person chose stays: on or off.
  ScraperRepo updatedWith(RepositoryManifest manifest) => ScraperRepo(
    id: id,
    url: url,
    name: manifest.name,
    description: manifest.description,
    version: manifest.version,
    scrapers: [for (final entry in manifest.scrapers) ScraperInfo.fromEntry(id, entry)],
    enabled: enabled,
  );

  Map<String, Object?> toJson() => {
    'url': url,
    'name': name,
    if (description != null) 'description': description,
    if (version != null) 'version': version,
    'enabled': enabled,
    'scrapers': [for (final s in scrapers) s.toJson()],
  };
}

/// What a scraper is asked for.
@immutable
class ScraperParams {
  const ScraperParams({required this.tmdbId, required this.mediaType, this.season, this.episode, this.scraperId});

  /// A text, like Nuvio ("550").
  final String tmdbId;

  /// "movie" or "tv".
  final String mediaType;

  /// Null for a film: the scraper then gets `undefined`, as from Nuvio.
  final int? season;
  final int? episode;

  /// Nuvio's `SCRAPER_ID`: `{manifest address in lower case}:{id}`.
  final String? scraperId;

  /// What `__vx.run` takes. `settings` is Nuvio's `SCRAPER_SETTINGS`: Vixeo has no settings page
  /// for a scraper, so it always has its defaults.
  Map<String, Object?> toJson() => {
    'tmdbId': tmdbId,
    'mediaType': mediaType,
    'season': season,
    'episode': episode,
    'scraperId': scraperId ?? '',
    'settings': const <String, Object?>{},
  };
}

/// A stream link a scraper found (`docs/scrapers.md` §3), read as Nuvio reads it.
@immutable
class ScraperStream {
  const ScraperStream({
    required this.url,
    this.name,
    this.title,
    this.quality,
    this.size,
    this.language,
    this.type,
    this.headers = const {},
  });

  /// The most streams kept from one scraper.
  static const maxPerScraper = 100;

  /// Null for something that is not a playable link (no address, a `javascript:` address…). The
  /// address may also be given as `{ url }`, as Nuvio accepts.
  static ScraperStream? tryParse(Object? json) {
    if (json is! Map) return null;
    final raw = json['url'];
    final url = _text(raw) ?? (raw is Map ? _text(raw['url']) : null);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
    String? number(Object? v) => v is num ? '$v' : _text(v);
    return ScraperStream(
      url: url,
      name: _text(json['name']) ?? _text(json['title']) ?? _text(json['provider']),
      title: _text(json['title']),
      quality: number(json['quality']),
      size: number(json['size']),
      language: _text(json['language']),
      type: _text(json['type']),
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

  /// Nuvio's `name`: often the source and its language (« Coflix (VF) »).
  final String? name;

  /// Nuvio's `title`, the line its app shows (« [VF] Coflix [1080p] »…).
  final String? title;
  final String? quality;
  final String? size;

  /// The audio language the scraper says ("fr", "multi"…), shown only.
  final String? language;

  /// The format the scraper says: "hls" / "m3u8", "dash" / "mpd", "mp4", "mkv"…
  final String? type;

  /// What the player must send with the request (Referer, Origin…).
  final Map<String, String> headers;

  /// "m3u8" or "mp4" when the scraper or the address says so, else null (the player finds out).
  String? get streamType {
    switch (type?.toLowerCase()) {
      case 'hls' || 'm3u8':
        return 'm3u8';
      case 'mp4' || 'mkv' || 'webm' || 'progressive':
        return 'mp4';
    }
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    if (path.endsWith('.m3u8')) return 'm3u8';
    if (path.endsWith('.mp4') || path.endsWith('.mkv')) return 'mp4';
    return null;
  }

  /// What the sources panel writes: the line Nuvio shows (its title, else its name, else
  /// [fallback]), then the quality if the line does not say it, then the size:
  /// « [VF] Coflix [1080p] · 1.2 GB ».
  String label(String fallback) {
    final main = title ?? name ?? fallback;
    final q = quality;
    return [main, if (q != null && !main.toLowerCase().contains(q.toLowerCase())) q, ?size].join(' · ');
  }
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

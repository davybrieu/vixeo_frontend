import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/local_store.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'rating_source.dart';

export 'rating_source.dart';

// Ratings of other sites (IMDb, Rotten Tomatoes, Letterboxd…) from MDBList, through the API
// (`GET /catalog/ratings`, vixeo_backend/docs/notes.md). MDBList's quota is Vixeo's, shared by
// every account: the API keeps the ratings a few days for everyone and asks MDBList 200 titles at
// a time; the app asks the API for a whole row or page of cards in one request and keeps the
// answers a day on the device.

/// Ratings of a title on the sites of [RatingSource], on each site's scale (none: not rated there).
@immutable
class TitleRatings {
  const TitleRatings(this.values);

  factory TitleRatings.fromJson(Map<String, dynamic> json) => TitleRatings({
    for (final source in RatingSource.values)
      if (json[source.name] case final num value when value > 0) source: value.toDouble(),
  });

  /// Not known by MDBList, or not asked (MDBList unavailable).
  static const empty = TitleRatings({});

  final Map<RatingSource, double> values;

  double? operator [](RatingSource source) => values[source];

  bool get isEmpty => values.isEmpty;
}

/// The rating a title shows: the profile's site, else TMDb (developer's request, 20/11/2026: no
/// IMDb in between). [loading] while its ratings are asked: nothing is shown yet, so that a rating
/// never changes once shown.
@immutable
class ShownRating {
  const ShownRating._(this.source, this.value, {this.loading = false});

  static const waiting = ShownRating._(null, null, loading: true);
  static const none = ShownRating._(null, null);

  /// The rating for [preferred] among [ratings] (MDBList) and [tmdb] (the title's TMDb average).
  factory ShownRating.pick(RatingSource preferred, TitleRatings? ratings, double tmdb) {
    if (preferred != RatingSource.tmdb) {
      final value = ratings?[preferred];
      if (value != null) return ShownRating._(preferred, value);
    }
    if (tmdb > 0) return ShownRating._(RatingSource.tmdb, tmdb);
    final fromMdbList = ratings?[RatingSource.tmdb];
    return fromMdbList == null ? none : ShownRating._(RatingSource.tmdb, fromMdbList);
  }

  final RatingSource? source;
  final double? value;
  final bool loading;

  bool get isNone => source == null || value == null;

  /// Out of 1, to compare ratings of different sites (sorting, « Note » filter of « Ma liste »).
  double? get fraction => isNone ? null : value! / source!.scale;
}

/// Answer of `GET /catalog/ratings`: [available] false when the API could not ask MDBList for some
/// titles now (they are missing from [ratings]).
typedef RatingsAnswer = ({Map<TitleRef, TitleRatings> ratings, bool available});

class RatingsRepository {
  RatingsRepository(this._api);

  final ApiClient _api;

  /// Ratings of up to 100 titles in one request.
  Future<RatingsAnswer> ratings(List<TitleRef> titles) async {
    final ids = titles.map((t) => '${t.type.name}:${t.id}').join(',');
    // The API may have to ask MDBList: never wait long, TMDb's rating is shown instead.
    final json = await _api.get('/catalog/ratings', query: {'ids': ids}, receiveTimeout: const Duration(seconds: 8));
    final data = json['data'];
    return (
      ratings: <TitleRef, TitleRatings>{
        if (data is List)
          for (final item in data.whereType<Map<String, dynamic>>())
            if (item['id'] case final int id)
              (type: MediaType.parse(item['type']), id: id): TitleRatings.fromJson(item),
      },
      available: json['available'] != false,
    );
  }
}

/// Asks the ratings of the titles on screen together and keeps them: in memory, and a day on the
/// device ([store]) so that a launch shows the ratings of the titles already seen at once.
///
/// [get] gathers the titles asked during a frame (the cards of a row or a page, built together)
/// into one request (100 titles at most); a title already asked waits for the same answer. A
/// title the API could not ask MDBList for now, or a failed request, is asked again after
/// [retryAfter], TMDb's rating being shown meanwhile.
class RatingsLoader {
  RatingsLoader({required this.fetch, this.store, DateTime Function()? now}) : _now = now ?? DateTime.now {
    // Never waited for: requests leave at once, and titles still waiting get the kept ratings as
    // soon as they are read (usually before the answer).
    unawaited(_restore());
  }

  final Future<RatingsAnswer> Function(List<TitleRef> titles) fetch;
  final LocalStore? store;
  final DateTime Function() _now;

  static const batchSize = 100;
  static const ttl = Duration(hours: 24);
  static const retryAfter = Duration(minutes: 2);
  static const storeKey = 'vixeo.ratings';

  /// Titles kept on the device, the most recent.
  static const maxStored = 1500;

  final _entries = <TitleRef, _Entry>{};
  final _waiting = <TitleRef, Completer<TitleRatings>>{};
  final _pending = <TitleRef>[];
  bool _flushScheduled = false;
  bool _cleared = false;
  Timer? _saveTimer;
  bool _disposed = false;

  /// Ratings already known and fresh, null otherwise.
  TitleRatings? peek(TitleRef title) {
    final entry = _entries[title];
    return entry != null && entry.expires.isAfter(_now()) ? entry.ratings : null;
  }

  /// Ratings of [title]; never fails ([TitleRatings.empty] when they can't be had now).
  Future<TitleRatings> get(TitleRef title) {
    final known = peek(title);
    if (known != null) return Future.value(known);
    final waiting = _waiting[title];
    if (waiting != null) return waiting.future;
    final completer = Completer<TitleRatings>();
    _waiting[title] = completer;
    _pending.add(title);
    if (!_flushScheduled) {
      _flushScheduled = true;
      // After the frame being built: its other cards join the same request.
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  /// Ratings of several titles (asked together).
  Future<Map<TitleRef, TitleRatings>> getMany(Iterable<TitleRef> titles) async {
    final list = titles.toSet().toList();
    final values = await Future.wait(list.map(get));
    return {for (final (i, title) in list.indexed) title: values[i]};
  }

  /// Asks the ratings of [titles] now if they aren't known (a row or a page of cards): the cards
  /// then find them, without a request each.
  void prefetch(Iterable<TitleRef> titles) {
    for (final title in titles) {
      if (peek(title) == null) unawaited(get(title));
    }
  }

  /// « Vider le cache »: forgets every rating, on the device too (not waited for).
  void clear() {
    _cleared = true;
    _entries.clear();
    _saveTimer?.cancel();
    unawaited(_write(null));
  }

  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    final titles = [..._pending];
    _pending.clear();
    final ask = <TitleRef>[];
    for (final title in titles) {
      final known = peek(title);
      if (known == null) {
        ask.add(title);
      } else {
        _complete(title, known);
      }
    }

    for (var i = 0; i < ask.length; i += batchSize) {
      final chunk = ask.sublist(i, math.min(i + batchSize, ask.length));
      RatingsAnswer? answer;
      try {
        answer = await fetch(chunk);
      } catch (_) {
        // Network, API: TMDb's rating meanwhile, asked again later.
      }
      final now = _now();
      for (final title in chunk) {
        final ratings = answer?.ratings[title];
        _entries[title] = ratings == null
            ? _Entry(TitleRatings.empty, now.add(retryAfter), kept: false)
            : _Entry(ratings, now.add(ttl), fetched: now);
        _complete(title, ratings ?? TitleRatings.empty);
      }
    }
    if (ask.isNotEmpty) _scheduleSave();
  }

  void _complete(TitleRef title, TitleRatings ratings) {
    final completer = _waiting.remove(title);
    if (completer != null && !completer.isCompleted) completer.complete(ratings);
  }

  void _scheduleSave() {
    if (store == null || _disposed) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), _save);
  }

  // Stored as {"v": 1, "sources": ["imdb", …], "items": {"movie:550": [fetched (s), imdb, …]}}.
  Future<void> _save() async {
    final now = _now();
    final kept = [
      for (final MapEntry(key: title, value: entry) in _entries.entries)
        if (entry.kept && entry.expires.isAfter(now)) (title, entry),
    ]..sort((a, b) => b.$2.fetched.compareTo(a.$2.fetched));
    final json = {
      'v': 1,
      'sources': [for (final s in RatingSource.values) s.name],
      'items': {
        for (final (title, entry) in kept.take(maxStored))
          '${title.type.name}:${title.id}': [
            entry.fetched.millisecondsSinceEpoch ~/ 1000,
            for (final s in RatingSource.values) entry.ratings[s],
          ],
      },
    };
    await _write(jsonEncode(json));
  }

  Future<void> _write(String? value) async {
    try {
      await store?.write(storeKey, value);
    } catch (_) {
      // Storage unavailable: the ratings stay in memory.
    }
  }

  Future<void> _restore() async {
    try {
      final raw = await store?.read(storeKey);
      if (raw == null || _cleared) return;
      final json = jsonDecode(raw);
      if (json is! Map || json['v'] != 1 || json['sources'] is! List || json['items'] is! Map) return;
      final sources = [for (final name in json['sources'] as List) RatingSource.values.asNameMap()[name]];
      final now = _now();
      for (final item in (json['items'] as Map).entries) {
        final parts = '${item.key}'.split(':');
        final value = item.value;
        if (parts.length != 2 || value is! List || value.isEmpty) continue;
        final id = int.tryParse(parts[1]);
        final seconds = value.first;
        if (id == null || seconds is! int) continue;
        final fetched = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        final expires = fetched.add(ttl);
        final TitleRef title = (type: MediaType.parse(parts[0]), id: id);
        // An answer of this launch wins.
        if (!expires.isAfter(now) || _entries.containsKey(title)) continue;
        final values = value.sublist(1);
        final ratings = TitleRatings({
          for (var i = 0; i < values.length && i < sources.length; i++)
            if (sources[i] case final source?)
              if (values[i] case final num v when v > 0) source: v.toDouble(),
        });
        _entries[title] = _Entry(ratings, expires, fetched: fetched);
        // Asked meanwhile: answered now, before the request.
        _complete(title, ratings);
      }
    } catch (_) {
      // Nothing kept, or unreadable: asked again.
    }
  }
}

class _Entry {
  _Entry(this.ratings, this.expires, {DateTime? fetched, this.kept = true})
    : fetched = fetched ?? DateTime.fromMillisecondsSinceEpoch(0);

  final TitleRatings ratings;
  final DateTime expires;
  final DateTime fetched;

  /// Kept on the device (a real answer, not a failure).
  final bool kept;
}

/// Where the ratings are kept between launches.
final ratingsStoreProvider = Provider<LocalStore?>((ref) => ref.read(localStoreProvider));

final ratingsLoaderProvider = Provider<RatingsLoader>((ref) {
  final repository = RatingsRepository(ref.read(apiClientProvider));
  final loader = RatingsLoader(fetch: repository.ratings, store: ref.read(ratingsStoreProvider));
  ref.onDispose(loader.dispose);
  return loader;
});

/// Site whose rating the active profile wants (IMDb by default, and for guests).
final ratingSourceProvider = Provider<RatingSource>(
  (ref) => ref.watch(sessionProvider.select((s) => s.profile?.ratingSource)) ?? RatingSource.imdb,
);

/// Ratings of one title, asked with the other cards of the frame (already known: at once).
final titleRatingsProvider = FutureProvider.autoDispose.family<TitleRatings, TitleRef>((ref, title) {
  final loader = ref.watch(ratingsLoaderProvider);
  final known = loader.peek(title);
  if (known != null) return known;
  return loader.get(title);
});

/// Ratings of several titles, keyed like [titlesKey] ("movie:550,tv:1399"): « Ma liste » sorts and
/// filters with them.
final titlesRatingsProvider = FutureProvider.autoDispose.family<Map<TitleRef, TitleRatings>, String>((ref, key) {
  final titles = [
    for (final part in key.split(','))
      if (part.split(':') case [final type, final id] when int.tryParse(id) != null)
        (type: MediaType.parse(type), id: int.parse(id)),
  ];
  return ref.watch(ratingsLoaderProvider).getMany(titles);
});

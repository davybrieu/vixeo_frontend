// What the future player needs besides the video (vixeo_backend/docs/lecture.md): moments to
// skip (TheIntroDB, through our API) and subtitles (OpenSubtitles, through our API, as WebVTT).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/models.dart';

/// Kinds of moments TheIntroDB knows.
enum SkipKind {
  intro('Passer le générique'),
  recap('Passer le résumé'),
  credits('Passer le générique de fin'),
  preview('Passer l’aperçu');

  const SkipKind(this.buttonLabel);

  /// Text of the "Passer" button shown when the profile doesn't skip it by itself.
  final String buttonLabel;

  /// Whether this profile skips it by itself.
  bool autoFor(Profile profile) => switch (this) {
    SkipKind.intro => profile.skipIntro,
    SkipKind.recap => profile.skipRecap,
    SkipKind.credits => profile.skipCredits,
    SkipKind.preview => profile.skipPreview,
  };
}

/// One moment, in milliseconds: no start = from the beginning, no end = to the end.
@immutable
class SkipSegment {
  const SkipSegment(this.kind, {this.startMs, this.endMs});

  final SkipKind kind;
  final int? startMs;
  final int? endMs;

  Duration get start => Duration(milliseconds: startMs ?? 0);

  /// Where the player jumps to (null = the end of the video: next episode).
  Duration? get end => endMs == null ? null : Duration(milliseconds: endMs!);

  bool contains(Duration position) => position >= start && (endMs == null || position < Duration(milliseconds: endMs!));
}

@immutable
class SkipSegments {
  const SkipSegments(this.segments);

  factory SkipSegments.fromJson(Map<String, dynamic> json) => SkipSegments([
    for (final kind in SkipKind.values)
      for (final s in (json[kind.name] as List? ?? const []).whereType<Map<String, dynamic>>())
        SkipSegment(kind, startMs: s['start_ms'] as int?, endMs: s['end_ms'] as int?),
  ]);

  static const none = SkipSegments([]);

  final List<SkipSegment> segments;

  /// The moment playing at [position], if any (the player then skips it or shows "Passer").
  SkipSegment? at(Duration position) {
    for (final segment in segments) {
      if (segment.contains(position)) return segment;
    }
    return null;
  }
}

/// A subtitle file found for a title (OpenSubtitles).
@immutable
class SubtitleOption {
  const SubtitleOption({
    required this.fileId,
    required this.language,
    this.release,
    this.hearingImpaired = false,
    this.aiTranslated = false,
    this.downloads = 0,
  });

  factory SubtitleOption.fromJson(Map<String, dynamic> json) => SubtitleOption(
    fileId: json['file_id'] as int,
    language: json['language'] as String? ?? '',
    release: json['release'] as String?,
    hearingImpaired: json['hearing_impaired'] as bool? ?? false,
    aiTranslated: json['ai_translated'] as bool? ?? false,
    downloads: json['downloads'] as int? ?? 0,
  );

  final int fileId;
  final String language;
  final String? release;
  final bool hearingImpaired;
  final bool aiTranslated;
  final int downloads;
}

/// A movie, or an episode of a TV show.
typedef PlaybackItem = ({MediaType type, int id, int? season, int? episode});

/// A player link resolved into a playable stream by the API (through the scraper's extractors).
@immutable
class ResolvedStream {
  const ResolvedStream({required this.stream, this.streamType, this.extractor, this.headers = const {}});

  factory ResolvedStream.fromJson(Map<String, dynamic> json) => ResolvedStream(
    stream: json['stream'] as String,
    streamType: json['stream_type'] as String?,
    extractor: json['extractor'] as String?,
    headers: (json['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
  );

  /// Playable URL: an HLS `.m3u8` playlist or a progressive `.mp4` file.
  final String stream;

  /// "m3u8" or "mp4", when the extractor says so.
  final String? streamType;

  /// Extractor that resolved the link ("voe"…), null for the generic one.
  final String? extractor;

  /// HTTP headers the player must send (Referer, Origin…).
  final Map<String, String> headers;
}

class PlaybackRepository {
  PlaybackRepository(this._api);

  final ApiClient _api;

  static String _base(PlaybackItem item) => item.type == MediaType.movie
      ? '/catalog/movie/${item.id}'
      : '/catalog/tv/${item.id}/season/${item.season}/episode/${item.episode}';

  Future<SkipSegments> segments(PlaybackItem item) async =>
      SkipSegments.fromJson((await _api.get('${_base(item)}/segments'))['data'] as Map<String, dynamic>? ?? const {});

  /// Resolves a player link into a playable stream, through the API.
  ///
  /// Throws an [ApiException] when no extractor knows the link (502): the player then shows an
  /// error instead of falling back to the raw player page, which cannot be played.
  Future<ResolvedStream> resolve(String url) async {
    final json = await _api.post('/catalog/resolve', body: {'url': url});
    return ResolvedStream.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Subtitles in [languages] (preferred first); without them, the profile's language.
  Future<List<SubtitleOption>> subtitles(PlaybackItem item, {List<String>? languages}) async {
    final json = await _api.get(
      '${_base(item)}/subtitles',
      query: {'languages': languages == null || languages.isEmpty ? null : languages.join(',')},
    );
    final data = json['data'];
    return data is List ? data.whereType<Map<String, dynamic>>().map(SubtitleOption.fromJson).toList() : const [];
  }

  /// The text of a subtitle file, as WebVTT (for the player's captions).
  Future<String> subtitleFile(int fileId) => _api.getText('/catalog/subtitles/$fileId');
}

final playbackRepositoryProvider = Provider<PlaybackRepository>(
  (ref) => PlaybackRepository(ref.read(apiClientProvider)),
);

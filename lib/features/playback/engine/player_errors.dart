/// Reading what players say when they fail: plain Dart, no plugin, so it is tested as is.
library;

import 'player_engine.dart';

/// What a browser says when it refuses to start a video nobody asked it to start (autoplay
/// policy): `NotAllowedError`, with a sentence that differs in Chrome, Firefox and Safari.
bool looksLikeAutoplayRefusal(String message) {
  final text = message.toLowerCase();
  return text.contains('notallowederror') ||
      text.contains("didn't interact") ||
      text.contains('not allowed by the user agent') ||
      text.contains('user gesture') ||
      text.contains('user activation');
}

/// Sorts a player's error message (video_player's `MEDIA_ERR_…`, ExoPlayer's, AVPlayer's) into a
/// [PlayerErrorKind]. A message nobody recognises is [PlayerErrorKind.unknown].
PlayerErrorKind classifyPlayerError(String message) {
  final text = message.toLowerCase();
  bool has(List<String> words) => words.any(text.contains);

  if (has(['drm', 'key system', 'keysystem', 'license', 'licence', 'fairplay', 'widevine', 'encrypted'])) {
    return PlayerErrorKind.drm;
  }
  if (has(['cors', 'cross-origin', 'cross origin', 'access-control-allow-origin'])) return PlayerErrorKind.cors;
  if (has([
    'media_err_src_not_supported',
    'not supported',
    'unsupported',
    'no supported',
    'format error',
    'unsuitable',
    'unrecognized',
    'demuxer_error',
    'manifestincompatiblecodecs',
    'incompatiblecodecs',
    'addcodec',
    'cannot open',
  ])) {
    return PlayerErrorKind.unsupported;
  }
  if (has(['media_err_decode', 'decode', 'decoder', 'pipeline_error'])) return PlayerErrorKind.decode;
  if (has([
    'media_err_network',
    'network',
    'timeout',
    'timed out',
    'connection',
    'unreachable',
    'failed to fetch',
    'http',
    'socket',
    'host',
    'internet',
  ])) {
    return PlayerErrorKind.network;
  }
  return PlayerErrorKind.unknown;
}

/// Sorts an hls.js fatal error (`data.type`, `data.details`, the HTTP status of the failed
/// request: 0 when the browser gave no answer to the page, which is also what a CORS refusal
/// looks like).
PlayerErrorKind classifyHlsError({required String type, required String details, int? httpStatus}) {
  final d = details.toLowerCase();
  if (type == 'keySystemError' || d.startsWith('keysystem')) return PlayerErrorKind.drm;
  if (d.contains('incompatiblecodecs') || d.contains('addcodec') || d == 'manifestparsingerror') {
    return PlayerErrorKind.unsupported;
  }
  if (type == 'networkError') return PlayerErrorKind.network;
  if (type == 'mediaError') return PlayerErrorKind.decode;
  if (type == 'muxError') return PlayerErrorKind.unsupported;
  return PlayerErrorKind.unknown;
}

/// The sentence shown to the viewer. [fallback] is the screen's usual one (« Impossible de lire
/// cette chaîne. »), kept when the cause is unknown.
String playerErrorMessage(PlayerError? error, {required String fallback, required bool web}) =>
    switch (error?.kind) {
      PlayerErrorKind.network => 'Problème de connexion : la vidéo ne se charge pas.',
      PlayerErrorKind.cors => 'Ce flux n’autorise pas la lecture dans un navigateur.',
      PlayerErrorKind.unsupported || PlayerErrorKind.decode =>
        web
            ? 'Ce format vidéo n’est pas pris en charge par ce navigateur.'
            : 'Ce format vidéo n’est pas pris en charge par cet appareil.',
      PlayerErrorKind.drm => 'Ce contenu protégé ne peut pas être lu ici.',
      PlayerErrorKind.unknown || null => fallback,
    };

/// Headers a page is not allowed to set: the browser sends its own (and logs a refusal for each
/// one a script tries to set).
const _forbiddenHeaders = {
  'accept-charset',
  'accept-encoding',
  'access-control-request-headers',
  'access-control-request-method',
  'connection',
  'content-length',
  'cookie',
  'date',
  'dnt',
  'expect',
  'host',
  'keep-alive',
  'origin',
  'referer',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'user-agent',
  'via',
};

/// The [headers] a browser lets a page send with a request.
Map<String, String> browserHeaders(Map<String, String> headers) => {
  for (final entry in headers.entries)
    if (!_forbiddenHeaders.contains(entry.key.toLowerCase()) &&
        !entry.key.toLowerCase().startsWith('sec-') &&
        !entry.key.toLowerCase().startsWith('proxy-'))
      entry.key: entry.value,
};

/// Which engine plays a stream in a browser.
enum WebEngineChoice { html5, hlsJs }

/// The browser's own player whenever it plays the stream itself; hls.js only for HLS in a
/// browser that does not (Chrome, Firefox, Edge on a computer), so its script is not even
/// downloaded elsewhere (Safari).
///
/// One exception: a stream that needs headers a page may send. `<video>` sends none, so hls.js
/// plays it wherever it can run ([mediaSource]).
WebEngineChoice chooseWebEngine({
  required bool hls,
  required bool nativeHls,
  required bool mediaSource,
  bool needsHeaders = false,
}) {
  if (!hls) return WebEngineChoice.html5;
  if (nativeHls && !(needsHeaders && mediaSource)) return WebEngineChoice.html5;
  return mediaSource ? WebEngineChoice.hlsJs : WebEngineChoice.html5;
}

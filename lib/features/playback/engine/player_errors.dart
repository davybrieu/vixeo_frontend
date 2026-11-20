/// Reading what players say when they fail: plain Dart, no plugin, so it is tested as is.
library;

import 'player_engine.dart';

/// Sorts a player's error message (video_player's, ExoPlayer's, AVPlayer's, mpv's) into a
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

/// The sentence shown to the viewer. [fallback] is the screen's usual one (« Impossible de lire
/// cette chaîne. »), kept when the cause is unknown.
String playerErrorMessage(PlayerError? error, {required String fallback}) => switch (error?.kind) {
      PlayerErrorKind.network || PlayerErrorKind.cors => 'Problème de connexion : la vidéo ne se charge pas.',
      PlayerErrorKind.unsupported ||
      PlayerErrorKind.decode => 'Ce format vidéo n’est pas pris en charge par cet appareil.',
      PlayerErrorKind.drm => 'Ce contenu protégé ne peut pas être lu ici.',
      PlayerErrorKind.unknown || null => fallback,
    };

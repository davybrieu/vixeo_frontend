import 'package:material_ui/material_ui.dart';

import '../playback/player_screen.dart';
import 'models.dart';

/// Compatibility entry point: all channel and VOD playback uses PlayerScreen.
class LivePlayerScreen extends StatelessWidget {
  const LivePlayerScreen({
    super.key,
    required this.title,
    this.stream,
    this.loadStream,
    this.returnLocation,
  }) : assert(stream != null || loadStream != null);

  final String title;
  final TvStream? stream;
  final Future<TvStream> Function()? loadStream;
  final String? returnLocation;

  static const hideDelay = PlayerScreen.hideDelay;
  static const stallTimeout = PlayerScreen.stallTimeout;

  @override
  Widget build(BuildContext context) => PlayerScreen.live(
    title: title,
    loadStream: () async => stream ?? await loadStream!(),
    returnLocation: returnLocation,
  );
}

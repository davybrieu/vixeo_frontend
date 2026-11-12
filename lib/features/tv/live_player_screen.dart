import 'package:flutter/material.dart';

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
    this.guest = false,
  }) : assert(stream != null || loadStream != null);

  final String title;
  final TvStream? stream;
  final Future<TvStream> Function()? loadStream;
  final String? returnLocation;
  final bool guest;

  static const hideDelay = Duration(seconds: 4);
  static const stallTimeout = Duration(seconds: 15);

  @override
  Widget build(BuildContext context) => PlayerScreen.live(
    title: title,
    loadStream: () async => stream ?? await loadStream!(),
    returnLocation: returnLocation,
    guestOverride: guest,
  );
}

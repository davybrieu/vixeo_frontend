import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/tv/live_player_screen.dart';
import 'package:vixeo/features/tv/models.dart';

/// Video playback without a real player: URLs in [failing] refuse to start; URLs in [stalled]
/// "play" with a still image (what a stream the browser cannot decode does on the web).
class FakeVideoPlatform extends VideoPlayerPlatform {
  FakeVideoPlatform({this.failing = const {}, this.stalled = const {}});

  final Set<String> failing;
  final Set<String> stalled;
  final _positions = <int, Duration>{};
  final created = <String>[];
  final volumes = <double>[];
  int plays = 0;
  int pauses = 0;
  final _events = <int, StreamController<VideoEvent>>{};
  final _urls = <int, String>{};
  bool _playing = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = created.length;
    created.add(options.dataSource.uri!);
    _urls[id] = options.dataSource.uri!;
    _events[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final controller = _events[playerId]!;
    scheduleMicrotask(() {
      if (failing.contains(_urls[playerId])) {
        controller.addError(PlatformException(code: 'error', message: 'dead stream'));
      } else {
        controller.add(
          VideoEvent(eventType: VideoEventType.initialized, size: const Size(1920, 1080), duration: Duration.zero),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    // Not awaited: the controller has already cancelled its subscription.
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
    _playing = true;
  }

  /// Counts the pauses of a playing stream (the controller also pauses before its first play).
  @override
  Future<void> pause(int playerId) async {
    if (_playing) pauses++;
    _playing = false;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async => volumes.add(volume);
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async {
    final position = _positions[playerId] ?? Duration.zero;
    if (!_playing || stalled.contains(_urls[playerId])) return position;
    return _positions[playerId] = position + const Duration(milliseconds: 100);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(int playerId, bool prevents) async {}
  @override
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(color: Colors.black);
}

const stream = TvStream(
  url: 'https://api.test/tv/stream/a',
  format: 'hls',
  sources: ['https://api.test/tv/stream/a', 'https://api.test/tv/stream/b'],
);

Future<FakeVideoPlatform> openPlayer(
  WidgetTester tester, {
  Set<String> failing = const {},
  Set<String> stalled = const {},
  Future<TvStream> Function()? loadStream,
}) async {
  final platform = FakeVideoPlatform(failing: failing, stalled: stalled);
  VideoPlayerPlatform.instance = platform;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildVixeoTheme(),
      home: LivePlayerScreen(title: 'France 2', stream: loadStream == null ? stream : null, loadStream: loadStream),
    ),
  );
  await settle(tester);
  return platform;
}

/// Lets the controllers start (and stop) between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    // Long enough for the player to see the image move (a position read every 500 ms).
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Leaves the player screen so its timers stop before the test ends.
Future<void> closePlayer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(LivePlayerScreen.hideDelay);
}

void main() {
  testWidgets('shows the controls: channel, live badge, pause, sound, back to live, source, full screen', (
    tester,
  ) async {
    final platform = await openPlayer(tester);

    expect(platform.created, ['https://api.test/tv/stream/a']);
    expect(platform.plays, 1);
    expect(find.text('France 2'), findsOneWidget);
    expect(find.text('EN DIRECT'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Couper le son'), findsOneWidget);
    expect(find.bySemanticsLabel('Revenir au direct'), findsOneWidget);
    expect(find.text('Source 1/2'), findsOneWidget);
    expect(find.bySemanticsLabel('Plein écran'), findsOneWidget);
    expect(find.bySemanticsLabel('Retour'), findsOneWidget);

    await closePlayer(tester);
  });

  testWidgets('play / pause, mute and next source', (tester) async {
    final platform = await openPlayer(tester);

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(platform.pauses, 1);
    expect(find.bySemanticsLabel('Lecture'), findsOneWidget);
    expect(find.text('EN DIRECT'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Lecture'));
    await tester.pump();
    expect(platform.plays, 2);

    await tester.tap(find.bySemanticsLabel('Couper le son'));
    await tester.pump();
    expect(platform.volumes.last, 0);
    expect(find.bySemanticsLabel('Activer le son'), findsOneWidget);

    await tester.tap(find.text('Source 1/2'));
    await settle(tester);
    expect(platform.created.last, 'https://api.test/tv/stream/b');
    expect(find.text('Source 2/2'), findsOneWidget);
    // The sound stays off on the new source.
    expect(platform.volumes.last, 0);

    await closePlayer(tester);
  });

  testWidgets('the controls hide while playing; a key brings them back without acting', (tester) async {
    final platform = await openPlayer(tester);

    await tester.pump(LivePlayerScreen.hideDelay);
    await tester.pump(const Duration(milliseconds: 300));
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('France 2'), matching: find.byType(AnimatedOpacity)),
    );
    expect(opacity.opacity, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<AnimatedOpacity>(find.ancestor(of: find.text('France 2'), matching: find.byType(AnimatedOpacity)))
          .opacity,
      1,
    );
    // The key only showed the controls: playback goes on.
    expect(platform.pauses, 0);

    // M mutes, K pauses.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(platform.volumes.last, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(platform.pauses, 1);

    await closePlayer(tester);
  });

  testWidgets('skips a dead source, then offers to retry when none plays', (tester) async {
    final platform = await openPlayer(tester, failing: {'https://api.test/tv/stream/a'});
    expect(platform.created, ['https://api.test/tv/stream/a', 'https://api.test/tv/stream/b']);
    expect(find.text('EN DIRECT'), findsOneWidget);
    await closePlayer(tester);

    final dead = await openPlayer(tester, failing: {'https://api.test/tv/stream/a', 'https://api.test/tv/stream/b'});
    expect(dead.created.length, 2);
    expect(find.text('Impossible de lire cette chaîne.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    await closePlayer(tester);
  });

  testWidgets('asks for the stream itself: a single loading, then playback', (tester) async {
    final platform = await openPlayer(tester, loadStream: () async => stream);
    expect(platform.created, ['https://api.test/tv/stream/a']);
    expect(find.text('EN DIRECT'), findsOneWidget);
    await closePlayer(tester);
  });

  testWidgets("shows the API's message when the stream cannot be had, and retries", (tester) async {
    var calls = 0;
    final platform = await openPlayer(
      tester,
      loadStream: () async {
        calls++;
        if (calls == 1) throw const ApiException('La TV en direct est indisponible.');
        return stream;
      },
    );
    expect(platform.created, isEmpty);
    expect(find.text('La TV en direct est indisponible.'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await settle(tester);
    expect(calls, 2);
    expect(find.text('EN DIRECT'), findsOneWidget);
    await closePlayer(tester);
  });

  testWidgets('a source whose image does not move keeps the controls, then gives way to the next', (tester) async {
    final platform = await openPlayer(tester, stalled: {'https://api.test/tv/stream/a'});
    expect(platform.created, ['https://api.test/tv/stream/a']);

    // Never a black screen alone: the controls and a spinner stay, without « EN DIRECT ».
    await tester.pump(LivePlayerScreen.hideDelay);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<AnimatedOpacity>(find.ancestor(of: find.text('France 2'), matching: find.byType(AnimatedOpacity)))
          .opacity,
      1,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('EN DIRECT'), findsNothing);

    await tester.pump(LivePlayerScreen.stallTimeout);
    await settle(tester);
    expect(platform.created.last, 'https://api.test/tv/stream/b');
    expect(find.text('EN DIRECT'), findsOneWidget);
    await closePlayer(tester);
  });

  testWidgets('no source moves: the error and « Réessayer » instead of a black screen', (tester) async {
    await openPlayer(tester, stalled: {'https://api.test/tv/stream/a', 'https://api.test/tv/stream/b'});
    for (var i = 0; i < 2; i++) {
      await tester.pump(LivePlayerScreen.stallTimeout);
      await settle(tester);
    }
    expect(find.text('Impossible de lire cette chaîne.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    await closePlayer(tester);
  });
}

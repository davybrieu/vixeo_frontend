import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/playback/engine/engine_factory.dart';
import 'package:vixeo/features/playback/engine/player_engine.dart';
import 'package:vixeo/features/playback/engine/player_errors.dart';
import 'package:vixeo/features/playback/playback.dart';
import 'package:vixeo/features/playback/player_screen.dart';
import 'package:vixeo/features/playback/webvtt.dart';
import 'package:vixeo/features/tv/live_player_screen.dart';
import 'package:vixeo/features/tv/models.dart';

/// An engine without any plugin: the player screen only knows [PlayerEngine], so its controls
/// are tested once for every platform.
class FakeEngine extends PlayerEngine {
  FakeEngine({this.openError, this.startsMuted = false});

  /// Thrown by [open] (a stream that cannot be played).
  final PlayerError? openError;

  /// The browser refuses a start with sound: the first [play] starts muted.
  final bool startsMuted;

  PlayerSource? opened;
  bool viewBuiltBeforeOpen = false;
  final _view = Completer<void>();
  int plays = 0;
  int pauses = 0;
  final seeks = <Duration>[];
  final volumes = <double>[];
  Duration _position = Duration.zero;

  @override
  String get name => 'fake';

  @override
  Future<void> open(PlayerSource source) async {
    opened = source;
    // Like the native player, which only exists once its view does: waits for the screen to
    // show the view (for ever if it does not).
    await _view.future;
    viewBuiltBeforeOpen = true;
    if (openError != null) throw openError!;
    value = value.copyWith(initialized: true, duration: source.live ? Duration.zero : const Duration(minutes: 10));
  }

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(playing: true, autoplayMuted: startsMuted && plays == 1 ? true : null);
  }

  @override
  Future<void> pause() async {
    pauses++;
    value = value.copyWith(playing: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    _position = position;
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    if (volume > 0 && value.autoplayMuted) value = value.copyWith(autoplayMuted: false);
  }

  @override
  Future<Duration?> get position async {
    if (value.playing) _position += const Duration(milliseconds: 100);
    return _position;
  }

  /// A failure in the middle of playback.
  void breakDown(PlayerError error) => value = value.copyWith(error: error, playing: false);

  @override
  Widget buildView(BuildContext context) {
    if (!_view.isCompleted) _view.complete();
    return const ColoredBox(color: Colors.black, child: SizedBox.expand(key: Key('fake-video')));
  }
}

const liveStream = TvStream(url: 'https://api.test/tv/stream/a', format: 'hls');

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> closePlayer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(PlayerScreen.hideDelay);
}

Future<FakeEngine> openLive(WidgetTester tester, FakeEngine engine) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerEngineFactoryProvider.overrideWithValue((source) => engine)],
      child: MaterialApp(
        theme: buildVixeoTheme(),
        home: const LivePlayerScreen(title: 'France 2', stream: liveStream),
      ),
    ),
  );
  await settle(tester);
  return engine;
}

/// A title's player with one provider (« Hôte ») and one link, chosen: the video plays.
Future<FakeEngine> openTitle(WidgetTester tester, PlayerScreen screen, {bool choose = true}) async {
  // A screen in landscape, like the player always is.
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final engine = FakeEngine();
  const link = StreamSource(provider: 'p', name: 'Film VF 1080P', url: 'https://host.test/embed/1');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(SignedOut.new),
        playbackRepositoryProvider.overrideWithValue(FakePlayback()),
        playerEngineFactoryProvider.overrideWithValue((source) => engine),
        sourceProvidersProvider.overrideWith((ref, item) async => const [SourceProvider(id: 'p', name: 'Hôte')]),
        providerSourcesProvider.overrideWith((ref, key) async => const [link]),
        titleProvider.overrideWith(
          (ref, key) async => TitleDetails(id: key.$2, type: key.$1, title: 'L’Odyssée', year: 2026),
        ),
        seasonProvider.overrideWith(
          (ref, key) async => Season(
            showId: key.$1,
            number: key.$2,
            name: 'Saison ${key.$2}',
            episodes: [Episode(id: 1, seasonNumber: key.$2, number: 2, name: 'Le Nord')],
          ),
        ),
      ],
      child: MaterialApp(theme: buildVixeoTheme(), home: screen),
    ),
  );
  await settle(tester);
  if (choose) {
    await tester.tap(find.text('Hôte'));
    await settle(tester);
    await tester.tap(find.text('Film VF 1080P'));
    await settle(tester);
  }
  return engine;
}

class SignedOut extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedOut);
}

class FakePlayback extends PlaybackRepository {
  FakePlayback() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<ResolvedStream> resolve(String url) async => const ResolvedStream(
    stream: 'https://cdn.test/film.mp4',
    streamType: 'mp4',
    headers: {'Referer': 'https://host.test/'},
  );

  @override
  Future<List<SubtitleOption>> subtitles(PlaybackItem item, {List<String>? languages}) async => const [
    SubtitleOption(fileId: 7, language: 'fr'),
  ];

  @override
  Future<String> subtitleFile(int fileId) async =>
      'WEBVTT\n\n1\n00:00:01.000 --> 00:00:04.000\n<i>Bonjour</i> tout le monde\n';
}

void main() {
  group('choosing the web engine', () {
    test('MP4 always plays in the browser’s own player', () {
      expect(chooseWebEngine(hls: false, nativeHls: false, mediaSource: true), WebEngineChoice.html5);
    });

    test('HLS: the browser’s own player when it has one (Safari), and hls.js is not loaded', () {
      expect(chooseWebEngine(hls: true, nativeHls: true, mediaSource: true), WebEngineChoice.html5);
      expect(chooseWebEngine(hls: true, nativeHls: true, mediaSource: false), WebEngineChoice.html5);
    });

    test('HLS: hls.js where the browser has none (Chrome, Firefox, Edge)', () {
      expect(chooseWebEngine(hls: true, nativeHls: false, mediaSource: true), WebEngineChoice.hlsJs);
    });

    test('HLS that needs headers: hls.js wherever it can run, <video> sends none', () {
      expect(
        chooseWebEngine(hls: true, nativeHls: true, mediaSource: true, needsHeaders: true),
        WebEngineChoice.hlsJs,
      );
      // An old iPhone (no Media Source Extensions): the native player is the only one.
      expect(
        chooseWebEngine(hls: true, nativeHls: true, mediaSource: false, needsHeaders: true),
        WebEngineChoice.html5,
      );
    });

    test('recognises an HLS stream from the API’s format, or from the URL', () {
      expect(const PlayerSource(url: 'https://a.test/x', format: StreamFormat.hls).isHls, isTrue);
      expect(const PlayerSource(url: 'https://a.test/live/index.m3u8?token=1').isHls, isTrue);
      expect(const PlayerSource(url: 'https://a.test/film.mp4').isHls, isFalse);
      expect(const PlayerSource(url: 'https://a.test/x.m3u8', format: StreamFormat.progressive).isHls, isFalse);
      expect(streamFormatFromApi('m3u8'), StreamFormat.hls);
      expect(streamFormatFromApi('hls'), StreamFormat.hls);
      expect(streamFormatFromApi('mp4'), StreamFormat.progressive);
      expect(streamFormatFromApi('ts'), isNull);
      expect(streamFormatFromApi(null), isNull);
    });

    test('only sends the headers a browser lets a page send', () {
      expect(
        browserHeaders({'Referer': 'https://a.test/', 'User-Agent': 'x', 'Origin': 'y', 'Authorization': 'Bearer t'}),
        {'Authorization': 'Bearer t'},
      );
      expect(browserHeaders({'Sec-Fetch-Mode': 'cors'}), isEmpty);
    });
  });

  group('reading player errors', () {
    test('sorts the messages of the HTML5 player', () {
      expect(classifyPlayerError('MEDIA_ERR_NETWORK: A network error occurred'), PlayerErrorKind.network);
      expect(classifyPlayerError('MEDIA_ERR_SRC_NOT_SUPPORTED: Format error'), PlayerErrorKind.unsupported);
      expect(classifyPlayerError('MEDIA_ERR_DECODE: PIPELINE_ERROR_DECODE'), PlayerErrorKind.decode);
      expect(classifyPlayerError('dead stream'), PlayerErrorKind.unknown);
    });

    test('sorts the fatal errors of hls.js', () {
      expect(
        classifyHlsError(type: 'networkError', details: 'manifestLoadError', httpStatus: 0),
        PlayerErrorKind.network,
      );
      expect(
        classifyHlsError(type: 'mediaError', details: 'manifestIncompatibleCodecsError'),
        PlayerErrorKind.unsupported,
      );
      expect(classifyHlsError(type: 'mediaError', details: 'bufferAddCodecError'), PlayerErrorKind.unsupported);
      expect(classifyHlsError(type: 'mediaError', details: 'fragParsingError'), PlayerErrorKind.decode);
      expect(classifyHlsError(type: 'keySystemError', details: 'keySystemNoAccess'), PlayerErrorKind.drm);
      expect(classifyHlsError(type: 'otherError', details: 'internalException'), PlayerErrorKind.unknown);
    });

    test('recognises a start refused by the browser (autoplay), in the three browsers’ words', () {
      expect(
        looksLikeAutoplayRefusal("play() failed because the user didn't interact with the document first."),
        isTrue,
      );
      expect(
        looksLikeAutoplayRefusal(
          'The play method is not allowed by the user agent or the platform in the current context',
        ),
        isTrue,
      );
      expect(looksLikeAutoplayRefusal('NotAllowedError'), isTrue);
      expect(looksLikeAutoplayRefusal('MEDIA_ERR_DECODE'), isFalse);
    });

    test('one sentence per cause, the usual one when the cause is unknown', () {
      String message(PlayerErrorKind kind, {bool web = true}) =>
          playerErrorMessage(PlayerError(kind), fallback: 'Impossible de lire cette chaîne.', web: web);
      expect(message(PlayerErrorKind.unknown), 'Impossible de lire cette chaîne.');
      expect(playerErrorMessage(null, fallback: 'x', web: true), 'x');
      expect(message(PlayerErrorKind.network), contains('connexion'));
      expect(message(PlayerErrorKind.cors), contains('navigateur'));
      expect(message(PlayerErrorKind.unsupported), contains('navigateur'));
      expect(message(PlayerErrorKind.unsupported, web: false), contains('appareil'));
      expect(message(PlayerErrorKind.drm), contains('protégé'));
    });
  });

  group('WebVTT subtitles', () {
    test('reads cues, without numbers, settings, tags or notes', () {
      final cues = parseWebVtt(
        'WEBVTT\r\n\r\nNOTE made for a test\r\n\r\n1\r\n00:00:01.000 --> 00:00:04.000 line:0 align:start\r\n'
        '<i>Bonjour</i> &amp; bienvenue\r\n\r\n'
        '01:02:03.500 --> 01:02:05.000\n<v Marie>Deux\nlignes\n\n'
        '00:10.000 --> 00:12.000\nSans heures\n',
      );
      expect(cues, hasLength(3));
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(seconds: 4));
      expect(cues[0].text, 'Bonjour & bienvenue');
      expect(cues[1].start, const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
      expect(cues[1].text, 'Deux\nlignes');
      expect(cues[2].start, const Duration(seconds: 10));
    });

    test('finds the cue on screen at a position', () {
      final cues = parseWebVtt('WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nUn\n\n00:00:05.000 --> 00:00:06.000\nDeux\n');
      expect(captionAt(cues, Duration.zero), isNull);
      expect(captionAt(cues, const Duration(seconds: 1)), 'Un');
      expect(captionAt(cues, const Duration(seconds: 4)), isNull);
      expect(captionAt(cues, const Duration(milliseconds: 5500)), 'Deux');
      expect(parseWebVtt('not a subtitle file'), isEmpty);
    });
  });

  group('one player screen for every engine', () {
    testWidgets('opens the stream with the platform’s engine: view first, then the same controls', (tester) async {
      final engine = await openLive(tester, FakeEngine());

      expect(engine.opened?.url, 'https://api.test/tv/stream/a');
      expect(engine.opened?.isHls, isTrue);
      expect(engine.opened?.live, isTrue);
      expect(engine.viewBuiltBeforeOpen, isTrue, reason: 'a native player needs its view before it opens');
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
      expect(engine.volumes, [1]);
      expect(engine.plays, 1);

      // The custom controls, unchanged.
      expect(find.text('France 2'), findsOneWidget);
      expect(find.text('EN DIRECT'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.bySemanticsLabel('Couper le son'), findsOneWidget);
      expect(find.bySemanticsLabel('Revenir au direct'), findsOneWidget);
      expect(find.bySemanticsLabel('Plein écran'), findsOneWidget);
      expect(find.bySemanticsLabel('Retour'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Pause'));
      await tester.pump();
      expect(engine.pauses, 1);
      expect(find.bySemanticsLabel('Lecture'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Lecture'));
      await tester.pump();
      expect(engine.plays, 2);

      await tester.tap(find.bySemanticsLabel('Couper le son'));
      await tester.pump();
      expect(engine.volumes.last, 0);

      await closePlayer(tester);
    });

    testWidgets('the player is always horizontal: landscape from its opening to its closing', (tester) async {
      final orientations = <List<Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') orientations.add(call.arguments as List<Object?>);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await openLive(tester, FakeEngine());
      expect(orientations.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);

      // Leaving full screen keeps the player horizontal.
      await tester.tap(find.bySemanticsLabel('Plein écran'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Quitter le plein écran'));
      await settle(tester);
      expect(orientations.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);

      // Closed: the rest of the app turns with the device again.
      await closePlayer(tester);
      expect(orientations.last, isEmpty);
    });

    testWidgets('a start the browser only allows muted: « Activer le son », and one press turns it on', (tester) async {
      final engine = await openLive(tester, FakeEngine(startsMuted: true));

      expect(find.text('EN DIRECT'), findsOneWidget);
      expect(find.bySemanticsLabel('Activer le son'), findsOneWidget);
      expect(find.bySemanticsLabel('Couper le son'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Activer le son'));
      await tester.pump();
      expect(engine.volumes.last, 1);
      expect(find.bySemanticsLabel('Couper le son'), findsOneWidget);

      await closePlayer(tester);
    });

    testWidgets('says why a stream cannot be played: network, CORS, format', (tester) async {
      await openLive(tester, FakeEngine(openError: const PlayerError(PlayerErrorKind.network, 'manifestLoadError')));
      expect(find.text('Problème de connexion : la vidéo ne se charge pas.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      await closePlayer(tester);

      await openLive(tester, FakeEngine(openError: const PlayerError(PlayerErrorKind.cors)));
      expect(find.text('Ce flux n’autorise pas la lecture dans un navigateur.'), findsOneWidget);
      await closePlayer(tester);

      await openLive(tester, FakeEngine(openError: const PlayerError(PlayerErrorKind.unknown)));
      expect(find.text('Impossible de lire cette chaîne.'), findsOneWidget);
      await closePlayer(tester);
    });

    testWidgets('a failure in the middle of playback shows the error, never a black screen', (tester) async {
      final engine = await openLive(tester, FakeEngine());
      expect(find.text('EN DIRECT'), findsOneWidget);

      engine.breakDown(const PlayerError(PlayerErrorKind.decode, 'bufferAppendError'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Ce format vidéo n’est pas pris en charge'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byKey(const Key('fake-video')), findsNothing);

      await closePlayer(tester);
    });

    testWidgets('a title: resolved stream and headers go to the engine; seek bar and WebVTT subtitles', (
      tester,
    ) async {
      final engine = FakeEngine();
      const source = StreamSource(provider: 'p', name: 'Film VF 1080P', url: 'https://host.test/embed/1');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedOut.new),
            playbackRepositoryProvider.overrideWithValue(FakePlayback()),
            playerEngineFactoryProvider.overrideWithValue((source) => engine),
            sourceProvidersProvider.overrideWith((ref, item) async => const [SourceProvider(id: 'p', name: 'Hôte')]),
            providerSourcesProvider.overrideWith((ref, key) async => const [source]),
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const PlayerScreen(type: MediaType.movie, id: 550),
          ),
        ),
      );
      await settle(tester);

      // The sources panel: one provider, one link.
      await tester.tap(find.text('Hôte'));
      await settle(tester);
      await tester.tap(find.text('Film VF 1080P'));
      await settle(tester);

      expect(engine.opened?.url, 'https://cdn.test/film.mp4');
      expect(engine.opened?.isHls, isFalse);
      expect(engine.opened?.live, isFalse);
      expect(engine.opened?.headers, {'Referer': 'https://host.test/'});
      expect(engine.plays, 1);

      // Seeking: half of the 10 minutes.
      final seekBar = tester.widget<Slider>(find.byType(Slider).first);
      seekBar.onChanged!(0.5);
      await tester.pump();
      expect(engine.seeks, [const Duration(minutes: 5)]);
      expect(find.textContaining('05:00'), findsWidgets);

      // Subtitles: chosen in the sheet, drawn by Flutter over the picture at the right time.
      await tester.tap(find.bySemanticsLabel('Sous-titres'));
      await settle(tester);
      await tester.tap(find.text('FR'));
      await settle(tester);
      expect(find.text('Bonjour tout le monde'), findsNothing);
      await engine.seekTo(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Bonjour tout le monde'), findsOneWidget);
      await engine.seekTo(const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('Bonjour tout le monde'), findsNothing);

      await closePlayer(tester);
    });

    testWidgets('a movie: back at the top left, title, year and « Via » its source, 10 s back and forward', (
      tester,
    ) async {
      final engine = await openTitle(tester, const PlayerScreen(type: MediaType.movie, id: 550));

      // The back button where the other pages have it: top left.
      final back = tester.getCenter(find.bySemanticsLabel('Retour'));
      expect(back.dx, lessThan(100));
      expect(back.dy, lessThan(100));

      expect(find.text('L’Odyssée'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Via Hôte'), findsOneWidget);
      expect(find.text('00:00 / 10:00'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.text('EN DIRECT'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Avancer de 10 secondes'));
      await tester.pump();
      expect(engine.seeks.last, const Duration(seconds: 10));
      expect(find.text('00:10 / 10:00'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Reculer de 10 secondes'));
      await tester.tap(find.bySemanticsLabel('Reculer de 10 secondes'));
      await tester.pump();
      // Never before the start.
      expect(engine.seeks.last, Duration.zero);

      // Five actions: all on screen, no arrow.
      for (final label in ['Sous-titres', 'Couper le son', 'Sources', 'Plein écran', 'Ouvrir en externe']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('Plus d’options'), findsNothing);

      await closePlayer(tester);
    });

    testWidgets('more than five actions: an arrow unfolds the others, pressed again it folds them', (tester) async {
      await openTitle(tester, const PlayerScreen(type: MediaType.tv, id: 1399, season: 1, episode: 2));
      expect(find.text('L’Odyssée'), findsOneWidget);
      expect(find.text('Saison 1 · Épisode 2 · Le Nord'), findsOneWidget);

      // The first five, then the arrow.
      for (final label in ['Sous-titres', 'Couper le son', 'Sources', 'Épisodes', 'Épisode suivant']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('Plein écran'), findsNothing);
      expect(find.bySemanticsLabel('Ouvrir en externe'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Plus d’options'));
      await tester.pump();
      expect(find.bySemanticsLabel('Plein écran'), findsOneWidget);
      expect(find.bySemanticsLabel('Ouvrir en externe'), findsOneWidget);
      expect(find.bySemanticsLabel('Plus d’options'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Moins d’options'));
      await tester.pump();
      expect(find.bySemanticsLabel('Ouvrir en externe'), findsNothing);
      expect(find.bySemanticsLabel('Plus d’options'), findsOneWidget);

      await closePlayer(tester);
    });

    testWidgets('before a source is chosen: seek bar and time are there, a white play opens the sources', (
      tester,
    ) async {
      final engine = await openTitle(tester, const PlayerScreen(type: MediaType.movie, id: 550), choose: false);
      // The sources panel, closed: the controls alone.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await settle(tester);
      expect(tester.getTopLeft(find.text('Sources')).dx, greaterThanOrEqualTo(1280));

      // The seek bar (still) and the time, at 0; no volume slider on a phone or a tablet.
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(find.text('00:00 / 00:00'), findsOneWidget);
      // Play is white, like the 10 s buttons, never greyed.
      expect(tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).color, Colors.white);
      expect(tester.widget<Icon>(find.byIcon(Icons.replay_10_rounded)).color, Colors.white);

      await tester.tap(find.bySemanticsLabel('Lecture'));
      await settle(tester);
      expect(tester.getTopLeft(find.text('Sources')).dx, lessThan(1280));
      expect(engine.opened, isNull);

      await closePlayer(tester);
    });
  });
}

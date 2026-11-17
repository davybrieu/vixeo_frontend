/// Picks the engine of the platform the app was compiled for.
///
/// A "conditional import": the compiler keeps one of the two files. A web build has no
/// `dart:io`, so it takes `engine_factory_web.dart` and never even reads the native plugin;
/// Android, iOS, desktop and the tests take `engine_factory_io.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_factory_io.dart' if (dart.library.js_interop) 'engine_factory_web.dart';
import 'player_engine.dart';

/// The factory the player screen uses. Tests replace it (`overrideWithValue`) with a fake engine.
final playerEngineFactoryProvider = Provider<PlayerEngineFactory>((ref) => createPlatformEngine);

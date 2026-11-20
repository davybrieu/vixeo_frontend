/// Picks the engine of the platform the app runs on (`engine_factory_io.dart`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_factory_io.dart';
import 'player_engine.dart';

/// The factory the player screen uses. Tests replace it (`overrideWithValue`) with a fake engine.
final playerEngineFactoryProvider = Provider<PlayerEngineFactory>((ref) => createPlatformEngine);

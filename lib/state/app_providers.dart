import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audio_storage.dart';
import '../data/document_store.dart';
import '../domain/app_settings.dart';
import '../domain/routine.dart';
import '../domain/track.dart';
import '../engine/drill_engine.dart';
import '../core/json.dart';

/// Everything read from disk before the first frame, so no screen ever has to
/// show a loading state for its own data.
final class StartupData {
  const StartupData({
    this.tracks = const [],
    this.routines = const [],
    this.settings = const AppSettings(),
  });

  final List<Track> tracks;
  final List<Routine> routines;
  final AppSettings settings;

  static Future<StartupData> load(DocumentStore store) async {
    final library = await store.read('library');
    final routines = await store.read('routines');
    final settings = await store.read('settings');
    return StartupData(
      tracks: parseList(library?['tracks'], Track.fromJson),
      routines: parseList(routines?['routines'], Routine.fromJson),
      settings: AppSettings.fromJson(settings ?? const {}),
    );
  }
}

// These four are created in main() (or in a test) and injected with
// `ProviderScope(overrides: …)`.
final startupDataProvider = Provider<StartupData>(
  (ref) => throw UnimplementedError('startupDataProvider must be overridden'),
);

final documentStoreProvider = Provider<DocumentStore>(
  (ref) => throw UnimplementedError('documentStoreProvider must be overridden'),
);

final audioStorageProvider = Provider<AudioStorage>(
  (ref) => throw UnimplementedError('audioStorageProvider must be overridden'),
);

final engineProvider = Provider<DrillEngine>(
  (ref) => throw UnimplementedError('engineProvider must be overridden'),
);

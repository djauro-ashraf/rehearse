import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rehearse/data/audio_storage.dart';
import 'package:rehearse/data/document_store.dart';
import 'package:rehearse/domain/app_settings.dart';
import 'package:rehearse/domain/loop.dart';
import 'package:rehearse/domain/marker.dart';
import 'package:rehearse/domain/routine.dart';
import 'package:rehearse/domain/track.dart';
import 'package:rehearse/engine/drill_engine.dart';
import 'package:rehearse/state/app_providers.dart';
import 'package:rehearse/state/library_notifier.dart';
import 'package:rehearse/state/practice_controller.dart';
import 'package:rehearse/state/routine_controller.dart';
import 'package:rehearse/state/routines_notifier.dart';
import 'package:rehearse/state/settings_notifier.dart';

import 'fakes.dart';

Track sampleTrack({
  String id = 't1',
  String title = 'Lesson',
  PracticeMemory memory = const PracticeMemory(),
  List<Loop> loops = const [],
  List<Marker> markers = const [],
  List<MarkerSet>? markerSets,
  int lastPlayedAtMs = 0,
}) =>
    Track(
      id: id,
      title: title,
      lastPlayedAtMs: lastPlayedAtMs,
      fileName: '$id.mp3',
      durationMs: 120000,
      sizeBytes: 100,
      addedAtMs: 1,
      memory: memory,
      loops: loops,
      markerSets: markerSets ??
          (markers.isEmpty
              ? const []
              : [MarkerSet(id: 's1', name: 'Set 1', createdAtMs: 0, markers: markers)]),
      activeMarkerSetId: markers.isEmpty && markerSets == null ? null : 's1',
    );

/// A complete app state graph (store, engine, providers) running on fakes.
class Harness {
  Harness({
    List<Track>? tracks,
    List<Routine> routines = const [],
    AppSettings settings = const AppSettings(),
  }) {
    backend = FakeBackend(durationMs: 120000);
    clock = SimClock(backend);
    engine = DrillEngine(backend, timers: clock.timers);
    store = MemoryDocumentStore();
    _live.add(this);
    container = ProviderContainer(overrides: [
      startupDataProvider.overrideWithValue(StartupData(
        tracks: tracks ?? [sampleTrack()],
        routines: routines,
        settings: settings,
      )),
      documentStoreProvider.overrideWithValue(store),
      audioStorageProvider.overrideWithValue(AudioStorage(Directory.systemTemp)),
      engineProvider.overrideWithValue(engine),
    ]);
  }

  static final List<Harness> _live = [];

  /// Disposes every harness created during a test (call from `tearDown`).
  static Future<void> disposeAll() async {
    for (final harness in List<Harness>.of(_live)) {
      await harness.dispose();
    }
    _live.clear();
  }

  late final FakeBackend backend;
  late final SimClock clock;
  late final DrillEngine engine;
  late final MemoryDocumentStore store;
  late final ProviderContainer container;

  PracticeController get practice =>
      container.read(practiceControllerProvider.notifier);
  PracticeState get practiceState => container.read(practiceControllerProvider);
  LibraryNotifier get library => container.read(libraryProvider.notifier);
  RoutinesNotifier get routines => container.read(routinesProvider.notifier);
  SettingsNotifier get settings => container.read(settingsProvider.notifier);
  RoutineController get routineController =>
      container.read(routineControllerProvider.notifier);

  Track track([String id = 't1']) => library.byId(id)!;

  /// Opens [id] for practice and lets async work settle.
  Future<void> open([String id = 't1']) async {
    await practice.open(id);
    await clock.settle();
  }

  /// Moves the playhead (the way a tap on the timeline would).
  Future<void> seek(int ms) async {
    await engine.seekTo(ms);
    await clock.settle();
  }

  Future<void> dispose() async {
    container.dispose();
    await engine.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/ids.dart';
import '../domain/gap.dart';
import '../domain/loop.dart';
import '../domain/loop_rules.dart';
import '../domain/marker.dart';
import '../domain/segments.dart';
import '../domain/speed_trainer.dart';
import '../domain/track.dart';
import '../engine/drill_engine.dart';
import '../engine/engine_state.dart';
import 'app_providers.dart';
import 'library_notifier.dart';
import 'routine_controller.dart';
import 'routines_notifier.dart';
import 'settings_notifier.dart';

/// Screen-level state of the practice view (what the engine doesn't know).
final class PracticeState {
  const PracticeState({
    this.trackId,
    this.activeLoopId,
    this.locked = false,
    this.zoom = false,
  });

  final String? trackId;

  /// The saved loop currently being drilled, if any.
  final String? activeLoopId;

  /// Freezes the A/B handles so a stray touch can't move them.
  final bool locked;

  /// Zooms the timeline in on the loop.
  final bool zoom;

  PracticeState copyWith({
    String? trackId,
    String? activeLoopId,
    bool clearActiveLoop = false,
    bool? locked,
    bool? zoom,
  }) =>
      PracticeState(
        trackId: trackId ?? this.trackId,
        activeLoopId: clearActiveLoop ? null : activeLoopId ?? this.activeLoopId,
        locked: locked ?? this.locked,
        zoom: zoom ?? this.zoom,
      );
}

enum MarkerOutcome { done, locked, needsMark, duplicate, noTrack }

/// What happened when you tapped "Mark here" / "Minimark here".
final class StampResult {
  const StampResult(this.outcome, {this.marker, this.needsName = false});

  final MarkerOutcome outcome;
  final Marker? marker;

  /// The stamp landed before existing ones, so it has no label yet.
  final bool needsName;
}

/// True when [loop] no longer matches what the engine is playing.
bool loopIsModified(Loop loop, EngineState s) =>
    s.hasLoop &&
    (loop.startMs != s.loopStartMs ||
        loop.endMs != s.loopEndMs ||
        loop.speed != s.speed ||
        loop.pitch != s.pitch ||
        loop.repeats != s.repeats ||
        loop.gap != s.gap);

/// Loops of [track] in the order they occur in the audio.
List<Loop> loopsByPosition(Track track) =>
    [...track.loops]..sort((a, b) => a.startMs.compareTo(b.startMs));

/// Every action of the practice screen. Screens call methods; this class
/// applies the rules (locks, previews, defaults) and talks to the engine.
class PracticeController extends Notifier<PracticeState> {
  Timer? _persistTimer;
  Timer? _debounce;
  String? _lastSavedJson;
  bool _wasPlaying = false;

  DrillEngine get _engine => ref.read(engineProvider);
  LibraryNotifier get _library => ref.read(libraryProvider.notifier);

  Track? get _track {
    final id = state.trackId;
    return id == null ? null : _library.byId(id);
  }

  bool get _routineActive =>
      ref.read(routineControllerProvider).runner.isActive;

  @override
  PracticeState build() {
    final engine = ref.watch(engineProvider);
    final subscription = engine.states.listen(_onEngineState);
    _persistTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => persist());
    ref.onDispose(() {
      subscription.cancel();
      _persistTimer?.cancel();
      _debounce?.cancel();
    });
    return const PracticeState();
  }

  // ── Opening ───────────────────────────────────────────────────────────────

  /// Opens [trackId] for practice. If it is already loaded (for example you
  /// tapped the mini player) playback simply carries on.
  Future<void> open(String trackId) async {
    final track = _library.byId(trackId);
    if (track == null) return;
    final engine = _engine;
    final routineActive = _routineActive;

    if (engine.state.trackId == trackId &&
        !routineActive &&
        engine.state.error == null) {
      state = state.copyWith(
        trackId: trackId,
        activeLoopId: track.memory.activeLoopId,
        clearActiveLoop: track.memory.activeLoopId == null,
      );
      return;
    }

    persist();
    if (routineActive) await ref.read(routineControllerProvider.notifier).stop();
    // A track you've never played starts at your default speed and pitch.
    final settings = ref.read(settingsProvider);
    final memory = track.hasBeenPlayed
        ? track.memory
        : track.memory.copyWith(
            speed: settings.defaultSpeed,
            pitch: settings.defaultPitch,
          );
    state = PracticeState(
      trackId: trackId,
      activeLoopId: track.loopById(memory.activeLoopId)?.id,
    );
    _lastSavedJson = null;
    await engine.setTrainer(null);
    await engine.load(
      trackId: track.id,
      path: ref.read(audioStorageProvider).pathFor(track.fileName),
      title: track.title,
      durationHintMs: track.durationMs,
      startMs: memory.positionMs,
      speed: memory.speed,
      pitch: memory.pitch,
      loopStartMs: memory.loopStartMs,
      loopEndMs: memory.loopEndMs,
      loopOn: memory.loopOn,
      repeats: memory.repeats,
      gap: memory.gap,
    );
    _library.touch(trackId);
  }

  /// Opens the previous/next track in the library's natural A→Z order (so
  /// `Lesson 2` comes before `Lesson 10`). Returns its id, or null at the ends.
  Future<String?> openAdjacent(int delta) async {
    final tracks = [...ref.read(libraryProvider)]
      ..sort((a, b) => naturalCompare(a.title, b.title));
    final index = tracks.indexWhere((t) => t.id == state.trackId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= tracks.length) return null;
    await open(tracks[target].id);
    return tracks[target].id;
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  Future<void> togglePlay() => _engine.toggle();

  Future<void> seek(int ms) => _engine.seekTo(ms);

  Future<void> skipBack() =>
      _engine.skip(-ref.read(settingsProvider).skipSeconds * 1000);

  Future<void> skipForward() =>
      _engine.skip(ref.read(settingsProvider).skipSeconds * 1000);

  // ── A / B ─────────────────────────────────────────────────────────────────

  void setA() {
    if (state.locked) return;
    final s = _engine.state;
    if (!s.hasTrack || s.durationMs <= 0) return;
    final position = _engine.positionMs;
    final end = s.loopEndMs;
    final region = end != null && position <= end - LoopRules.minLoopMs
        ? LoopRules.region(position, end, s.durationMs)
        : LoopRules.regionFrom(position, s.durationMs);
    if (region == null) return;
    _engine.setLoopRegion(region.$1, region.$2, loopOn: true);
  }

  void setB() {
    if (state.locked) return;
    final s = _engine.state;
    if (!s.hasTrack || s.durationMs <= 0) return;
    final position = _engine.positionMs;
    final start = s.loopStartMs;
    final region = start != null && position >= start + LoopRules.minLoopMs
        ? LoopRules.region(start, position, s.durationMs)
        : LoopRules.regionEndingAt(position, s.durationMs);
    if (region == null) return;
    _engine.setLoopRegion(region.$1, region.$2, loopOn: true);
    _previewB();
  }

  /// Sets A to an exact time (typed in by the user).
  void setAExact(int ms) {
    final s = _engine.state;
    if (state.locked || !s.hasTrack) return;
    final end = s.loopEndMs ?? (ms + LoopRules.defaultLoopMs);
    final region = LoopRules.region(ms, end, s.durationMs);
    if (region == null) return;
    _engine.setLoopRegion(region.$1, region.$2, loopOn: true);
    unawaited(_engine.seekTo(region.$1));
  }

  /// Sets B to an exact time (typed in by the user).
  void setBExact(int ms) {
    final s = _engine.state;
    if (state.locked || !s.hasTrack) return;
    final start = s.loopStartMs ?? (ms - LoopRules.defaultLoopMs);
    final region = LoopRules.region(start, ms, s.durationMs);
    if (region == null) return;
    _engine.setLoopRegion(region.$1, region.$2, loopOn: true);
    _previewB();
  }

  void nudgeA(int deltaMs) {
    final s = _engine.state;
    if (state.locked || !s.hasLoop) return;
    final engine = _engine;
    final a = LoopRules.clampStart(s.loopStartMs! + deltaMs, s.loopEndMs!);
    engine.setLoopRegion(a, s.loopEndMs!);
    _later(() => unawaited(engine.seekTo(a)));
  }

  void nudgeB(int deltaMs) {
    final s = _engine.state;
    if (state.locked || !s.hasLoop) return;
    final b =
        LoopRules.clampEnd(s.loopEndMs! + deltaMs, s.loopStartMs!, s.durationMs);
    _engine.setLoopRegion(s.loopStartMs!, b);
    _later(_previewB);
  }

  /// Live update while a handle is being dragged on the timeline.
  void dragRegion(int startMs, int endMs) {
    if (state.locked) return;
    _engine.setLoopRegion(startMs, endMs, loopOn: true);
  }

  /// Called when the finger lifts: audition the part that was just edited.
  void endDrag({required bool movedB}) {
    final s = _engine.state;
    if (!s.hasLoop) return;
    if (movedB) {
      _previewB();
    } else {
      unawaited(_engine.seekTo(s.loopStartMs!));
    }
  }

  Future<void> toggleLoop() async {
    final s = _engine.state;
    if (s.loopOn) return _engine.setLoopOn(false);
    if (!s.hasLoop) {
      final region =
          LoopRules.regionFrom(_engine.positionMs, s.durationMs);
      if (region == null) return;
      _engine.setLoopRegion(region.$1, region.$2, loopOn: true);
      return;
    }
    await _engine.setLoopOn(true);
  }

  void clearLoop() {
    if (state.locked) return;
    _engine.clearLoop();
    state = state.copyWith(clearActiveLoop: true);
  }

  void toggleLock() => state = state.copyWith(locked: !state.locked);

  void toggleZoom() => state = state.copyWith(zoom: !state.zoom);

  /// Plays the last few seconds before B, then carries on into the loop.
  void _previewB() {
    final settings = ref.read(settingsProvider);
    final s = _engine.state;
    if (!settings.previewEnabled || !s.hasLoop) return;
    final from = LoopRules.previewStart(
      s.loopStartMs!,
      s.loopEndMs!,
      settings.previewMs,
    );
    if (from == null) return; // the preview would be as long as the loop
    final engine = _engine;
    unawaited(engine.seekTo(from).then((_) => engine.play()));
  }

  void _later(void Function() action) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), action);
  }

  // ── Sound & repeats ───────────────────────────────────────────────────────

  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);

  Future<void> nudgeSpeed(int steps) =>
      _engine.setSpeed(_engine.state.speed + steps * LoopRules.speedStep);

  Future<void> setPitch(double semitones) => _engine.setPitch(semitones);

  void setRepeats(int repeats) => _engine.setRepeats(repeats);

  void setGap(Gap gap) => _engine.setGap(gap);

  Future<void> setTrainer(SpeedTrainer trainer) async {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(trainer: trainer));
    await _engine.setTrainer(trainer.enabled ? trainer : null);
  }

  // ── Saved loops ───────────────────────────────────────────────────────────

  /// Saves the current A–B and sound settings as a new loop.
  Loop? saveLoop({String? name}) {
    final s = _engine.state;
    final track = _track;
    if (track == null || !s.hasLoop) return null;
    final loop = Loop(
      id: newId(),
      name: name ?? 'Loop ${track.loops.length + 1}',
      startMs: s.loopStartMs!,
      endMs: s.loopEndMs!,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      speed: s.speed,
      pitch: s.pitch,
      repeats: s.repeats,
      gap: s.gap,
    );
    _library.upsertLoop(track.id, loop);
    state = state.copyWith(activeLoopId: loop.id);
    return loop;
  }

  /// Overwrites the active saved loop with the current settings.
  void updateActiveLoop() {
    final track = _track;
    final loop = track?.loopById(state.activeLoopId);
    final s = _engine.state;
    if (track == null || loop == null || !s.hasLoop) return;
    _library.upsertLoop(
      track.id,
      loop.copyWith(
        startMs: s.loopStartMs,
        endMs: s.loopEndMs,
        speed: s.speed,
        pitch: s.pitch,
        repeats: s.repeats,
        gap: s.gap,
      ),
    );
  }

  /// Loads a saved loop into the player and starts it.
  Future<void> applyLoop(Loop loop) async {
    state = state.copyWith(activeLoopId: loop.id);
    await _engine.applyLoop(
      startMs: loop.startMs,
      endMs: loop.endMs,
      speed: loop.speed,
      pitch: loop.pitch,
      repeats: loop.repeats,
      gap: loop.gap,
    );
    await _engine.play();
  }

  void renameLoop(String loopId, String name) {
    final track = _track;
    final loop = track?.loopById(loopId);
    final clean = name.trim();
    if (track == null || loop == null || clean.isEmpty) return;
    _library.upsertLoop(track.id, loop.copyWith(name: clean));
  }

  /// Puts back a loop that was just deleted (for "Undo").
  void restoreLoop(Loop loop) {
    final track = _track;
    if (track != null) _library.upsertLoop(track.id, loop);
  }

  /// Number of routines that include [loopId].
  int routinesUsing(String loopId) {
    final track = _track;
    if (track == null) return 0;
    return ref.read(routinesProvider.notifier).usageOfLoop(track.id, loopId);
  }

  void deleteLoop(String loopId) {
    final track = _track;
    if (track == null) return;
    _library.removeLoop(track.id, loopId);
    ref.read(routinesProvider.notifier).purgeLoop(track.id, loopId);
    if (state.activeLoopId == loopId) {
      state = state.copyWith(clearActiveLoop: true);
    }
  }

  // ── Marker sets, stamping and segments ───────────────────────────────────

  MarkerSet? get _activeSet => _track?.activeSet;

  /// Creates a marker at the playhead. Marks can be added anywhere; a
  /// Minimark needs a Mark before it (it nests inside that Mark's segment).
  /// Out-of-order stamps come back with `needsName` so the UI can ask.
  StampResult stamp(MarkerTier tier) {
    final track = _track;
    if (track == null || !_engine.state.hasTrack) {
      return const StampResult(MarkerOutcome.noTrack);
    }
    final set = _activeSet;
    if (set != null && set.isLocked(tier)) {
      return const StampResult(MarkerOutcome.locked);
    }
    final position = _engine.positionMs;
    final markers = set?.markers ?? const <Marker>[];
    if (tier == MarkerTier.minimark &&
        enclosingSegment(markers, position, track.durationMs) == null) {
      return const StampResult(MarkerOutcome.needsMark);
    }
    if (markers.any((m) => m.tier == tier && (m.positionMs - position).abs() < 300)) {
      return const StampResult(MarkerOutcome.duplicate);
    }
    final siblings = stampSiblings(tier, markers, position, track.durationMs);
    final label = stampLabel(siblings, position);
    final marker = Marker(
      id: newId(),
      label: label.label,
      positionMs: position,
      tier: tier,
    );
    final setId = _library.ensureMarkerSet(track.id);
    _library.addMarker(track.id, setId, marker);
    return StampResult(MarkerOutcome.done, marker: marker, needsName: label.needsName);
  }

  Marker? _markerById(String id) {
    for (final m in _activeSet?.markers ?? const <Marker>[]) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Applies [change] to one marker unless its tier is locked.
  MarkerOutcome _editMarker(String markerId, Marker Function(Marker) change) {
    final track = _track;
    final set = _activeSet;
    final marker = _markerById(markerId);
    if (track == null || set == null || marker == null) return MarkerOutcome.noTrack;
    if (set.isLocked(marker.tier)) return MarkerOutcome.locked;
    _library.updateMarker(track.id, set.id, change(marker));
    return MarkerOutcome.done;
  }

  MarkerOutcome renameMarker(String markerId, String label) =>
      _editMarker(markerId, (m) => m.copyWith(label: label.trim()));

  MarkerOutcome toggleSkip(String markerId) =>
      _editMarker(markerId, (m) => m.copyWith(skip: !m.skip));

  /// Moves a marker by a small amount (to fix tap lag), within the audio.
  MarkerOutcome nudgeMarker(String markerId, int deltaMs) {
    final duration = _track?.durationMs ?? 0;
    return _editMarker(
      markerId,
      (m) => m.copyWith(positionMs: (m.positionMs + deltaMs).clamp(0, duration)),
    );
  }

  MarkerOutcome moveMarker(String markerId, int positionMs) {
    final duration = _track?.durationMs ?? 0;
    return _editMarker(
      markerId,
      (m) => m.copyWith(positionMs: positionMs.clamp(0, duration)),
    );
  }

  MarkerOutcome removeMarker(String markerId) {
    final track = _track;
    final set = _activeSet;
    final marker = _markerById(markerId);
    if (track == null || set == null || marker == null) return MarkerOutcome.noTrack;
    if (set.isLocked(marker.tier)) return MarkerOutcome.locked;
    _library.removeMarker(track.id, set.id, markerId);
    return MarkerOutcome.done;
  }

  void clearMarkers() {
    final track = _track;
    final set = _activeSet;
    if (track == null || set == null) return;
    _library.updateMarkerSet(
      track.id,
      set.id,
      (s) => s.copyWith(markers: [
        if (s.lockedMarks) ...s.markers.where((m) => m.tier == MarkerTier.mark),
        if (s.lockedMinimarks) ...s.markers.where((m) => m.tier == MarkerTier.minimark),
      ]),
    );
  }

  void toggleMarkerLock(MarkerTier tier) {
    final track = _track;
    final set = _activeSet ?? _track?.activeSet;
    if (track == null) return;
    final id = set?.id ?? _library.ensureMarkerSet(track.id);
    _library.updateMarkerSet(
      track.id,
      id,
      (s) => tier == MarkerTier.mark
          ? s.copyWith(lockedMarks: !s.lockedMarks)
          : s.copyWith(lockedMinimarks: !s.lockedMinimarks),
    );
  }

  void createMarkerSet(String name) {
    final track = _track;
    if (track != null) _library.createMarkerSet(track.id, name);
  }

  void selectMarkerSet(String setId) {
    final track = _track;
    if (track != null) _library.selectMarkerSet(track.id, setId);
  }

  void renameMarkerSet(String setId, String name) {
    final track = _track;
    if (track != null) _library.renameMarkerSet(track.id, setId, name);
  }

  void deleteMarkerSet(String setId) {
    final track = _track;
    if (track != null) _library.deleteMarkerSet(track.id, setId);
  }

  // Segments (the audio between two markers)

  /// Plays one range once and pauses at its end, leaving the loop alone.
  Future<void> playRangeOnce(int startMs, int endMs) =>
      _engine.playRange(startMs, endMs);

  /// Loops a range, keeping the current speed, pitch, repeats and gap.
  Future<void> loopRange(int startMs, int endMs) async {
    final s = _engine.state;
    state = state.copyWith(clearActiveLoop: true);
    await _engine.applyLoop(
      startMs: startMs,
      endMs: endMs,
      speed: s.speed,
      pitch: s.pitch,
      repeats: s.repeats,
      gap: s.gap,
      keepTrainer: true,
    );
    await _engine.play();
  }

  List<MarkSegment> get _segments {
    final track = _track;
    return track == null ? const [] : buildSegments(track.markers, track.durationMs);
  }

  Future<void> loopSegment(int index) async {
    final segments = _segments;
    if (index < 0 || index >= segments.length) return;
    await loopRange(segments[index].startMs, segments[index].endMs);
  }

  /// Moves to the next/previous segment: looping it if a loop is on,
  /// otherwise just jumping there. "Previous" first restarts a segment you
  /// are already well into, like a music player.
  Future<void> jumpSegment(int delta) async {
    final segments = _segments;
    if (segments.isEmpty) return;
    final position = _engine.positionMs;
    final current = segmentIndexAt(segments, position);
    final restart = delta < 0 &&
        current >= 0 &&
        position - segments[current].startMs > 1500;
    final target = (restart ? current : current + delta).clamp(0, segments.length - 1);
    if (_engine.state.loopOn) {
      await loopSegment(target);
    } else {
      await _engine.seekTo(segments[target].startMs);
    }
  }

  /// Creates one saved loop per Mark segment (skipping ones that already
  /// exist), using the current speed, pitch and gap. Returns how many.
  int loopsFromMarkers() {
    final track = _track;
    if (track == null) return 0;
    final s = _engine.state;
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = <Loop>[];
    for (final segment in _segments) {
      final region =
          LoopRules.region(segment.startMs, segment.endMs, track.durationMs);
      if (region == null) continue;
      final exists = track.loops.any(
        (l) => l.startMs == region.$1 && l.endMs == region.$2,
      );
      if (exists) continue;
      created.add(Loop(
        id: newId(),
        name: 'Segment ${segment.mark.label}',
        startMs: region.$1,
        endMs: region.$2,
        createdAtMs: now,
        speed: s.speed,
        pitch: s.pitch,
        repeats: s.repeats,
        gap: s.gap,
      ));
    }
    _library.addLoops(track.id, created);
    return created.length;
  }

  // ── Persistence of "where I left off" ────────────────────────────────────

  void persist() {
    final trackId = state.trackId;
    final s = _engine.state;
    if (trackId == null || s.trackId != trackId || s.loading) return;
    if (s.error != null || _routineActive) return;
    final memory = PracticeMemory(
      positionMs: _engine.positionMs,
      speed: s.speed,
      pitch: s.pitch,
      loopStartMs: s.loopStartMs,
      loopEndMs: s.loopEndMs,
      loopOn: s.loopOn,
      repeats: s.repeats,
      gap: s.gap,
      activeLoopId: state.activeLoopId,
    );
    final json = jsonEncode(memory.toJson());
    if (json == _lastSavedJson) return;
    _lastSavedJson = json;
    _library.saveMemory(trackId, memory);
  }

  void _onEngineState(EngineState s) {
    if (_wasPlaying && !s.playing) persist();
    _wasPlaying = s.playing;
  }
}

final practiceControllerProvider =
    NotifierProvider<PracticeController, PracticeState>(PracticeController.new);

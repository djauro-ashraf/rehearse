import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import '../domain/loop.dart';
import '../domain/marker.dart';
import '../domain/track.dart';
import 'app_providers.dart';

/// All tracks with their loops and markers. Every change is saved.
class LibraryNotifier extends Notifier<List<Track>> {
  @override
  List<Track> build() => ref.read(startupDataProvider).tracks;

  Track? byId(String id) {
    for (final track in state) {
      if (track.id == id) return track;
    }
    return null;
  }

  void _commit(List<Track> tracks) {
    state = tracks;
    ref.read(documentStoreProvider).write('library', {
      'version': 1,
      'tracks': [for (final t in tracks) t.toJson()],
    });
  }

  /// Applies [change] to one track and saves.
  void mutate(String id, Track Function(Track) change) {
    var found = false;
    final next = [
      for (final track in state)
        if (track.id == id)
          () {
            found = true;
            return change(track);
          }()
        else
          track,
    ];
    if (found) _commit(next);
  }

  void add(Track track) => _commit([track, ...state]);

  void rename(String id, String title) {
    final clean = title.trim();
    if (clean.isEmpty) return;
    mutate(id, (t) => t.copyWith(title: clean));
  }

  void remove(String id) => _commit([
        for (final track in state)
          if (track.id != id) track,
      ]);

  void touch(String id) => mutate(
        id,
        (t) => t.copyWith(lastPlayedAtMs: DateTime.now().millisecondsSinceEpoch),
      );

  void saveMemory(String id, PracticeMemory memory) =>
      mutate(id, (t) => t.copyWith(memory: memory));

  // Loops

  void upsertLoop(String trackId, Loop loop) => mutate(trackId, (t) {
        final exists = t.loops.any((l) => l.id == loop.id);
        return t.copyWith(
          loops: exists
              ? [for (final l in t.loops) l.id == loop.id ? loop : l]
              : [...t.loops, loop],
        );
      });

  void addLoops(String trackId, List<Loop> loops) {
    if (loops.isEmpty) return;
    mutate(trackId, (t) => t.copyWith(loops: [...t.loops, ...loops]));
  }

  void removeLoop(String trackId, String loopId) => mutate(
        trackId,
        (t) => t.copyWith(loops: [
          for (final l in t.loops)
            if (l.id != loopId) l,
        ]),
      );

  /// Replaces the whole library (used by restore).
  void replaceAll(List<Track> tracks) => _commit(tracks);

  void setContentHash(String trackId, String hash) =>
      mutate(trackId, (t) => t.copyWith(contentHash: hash));

  // Marker sets

  /// Returns the id of the track's active marker set, creating a first one
  /// ("Set 1") if there is none yet.
  String ensureMarkerSet(String trackId) {
    final track = byId(trackId);
    if (track == null) return '';
    final active = track.activeSet;
    if (active != null) return active.id;
    final set = MarkerSet(
      id: newId(),
      name: 'Set 1',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    mutate(
      trackId,
      (t) => t.copyWith(markerSets: [set], activeMarkerSetId: set.id),
    );
    return set.id;
  }

  /// Adds a set and makes it the active one.
  MarkerSet createMarkerSet(String trackId, String name) {
    final set = MarkerSet(
      id: newId(),
      name: name.trim().isEmpty ? 'New set' : name.trim(),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    mutate(
      trackId,
      (t) => t.copyWith(markerSets: [...t.markerSets, set], activeMarkerSetId: set.id),
    );
    return set;
  }

  void selectMarkerSet(String trackId, String setId) =>
      mutate(trackId, (t) => t.copyWith(activeMarkerSetId: setId));

  void renameMarkerSet(String trackId, String setId, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    updateMarkerSet(trackId, setId, (s) => s.copyWith(name: clean));
  }

  void deleteMarkerSet(String trackId, String setId) => mutate(trackId, (t) {
        final rest = [
          for (final s in t.markerSets)
            if (s.id != setId) s,
        ];
        return t.copyWith(
          markerSets: rest,
          activeMarkerSetId: t.activeMarkerSetId == setId
              ? (rest.isEmpty ? null : rest.first.id)
              : t.activeMarkerSetId,
        );
      });

  void updateMarkerSet(
    String trackId,
    String setId,
    MarkerSet Function(MarkerSet) change,
  ) =>
      mutate(
        trackId,
        (t) => t.copyWith(markerSets: [
          for (final s in t.markerSets) s.id == setId ? change(s) : s,
        ]),
      );

  // Markers (always inside one set)

  void addMarker(String trackId, String setId, Marker marker) =>
      updateMarkerSet(trackId, setId, (s) => s.copyWith(markers: [...s.markers, marker]));

  void updateMarker(String trackId, String setId, Marker marker) =>
      updateMarkerSet(
        trackId,
        setId,
        (s) => s.copyWith(markers: [
          for (final m in s.markers) m.id == marker.id ? marker : m,
        ]),
      );

  void removeMarker(String trackId, String setId, String markerId) =>
      updateMarkerSet(
        trackId,
        setId,
        (s) => s.copyWith(markers: [
          for (final m in s.markers)
            if (m.id != markerId) m,
        ]),
      );

  void clearMarkers(String trackId, String setId, MarkerTier? tier) =>
      updateMarkerSet(
        trackId,
        setId,
        (s) => s.copyWith(markers: [
          if (tier != null)
            for (final m in s.markers)
              if (m.tier != tier) m,
        ]),
      );
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, List<Track>>(LibraryNotifier.new);

/// One track by id (null once it has been deleted).
final trackProvider = Provider.family<Track?, String>((ref, id) {
  for (final track in ref.watch(libraryProvider)) {
    if (track.id == id) return track;
  }
  return null;
});

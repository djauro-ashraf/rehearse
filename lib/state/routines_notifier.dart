import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import '../domain/routine.dart';
import 'app_providers.dart';

class RoutinesNotifier extends Notifier<List<Routine>> {
  @override
  List<Routine> build() => ref.read(startupDataProvider).routines;

  Routine? byId(String id) {
    for (final routine in state) {
      if (routine.id == id) return routine;
    }
    return null;
  }

  void _commit(List<Routine> routines) {
    state = routines;
    ref.read(documentStoreProvider).write('routines', {
      'version': 1,
      'routines': [for (final r in routines) r.toJson()],
    });
  }

  /// Replaces every routine (used by restore).
  void replaceAll(List<Routine> routines) => _commit(routines);

  /// Inserts a new routine or replaces the one with the same id.
  void upsert(Routine routine) {
    final stamped =
        routine.copyWith(updatedAtMs: DateTime.now().millisecondsSinceEpoch);
    final exists = state.any((r) => r.id == routine.id);
    _commit(exists
        ? [for (final r in state) r.id == routine.id ? stamped : r]
        : [stamped, ...state]);
  }

  void remove(String id) => _commit([
        for (final r in state)
          if (r.id != id) r,
      ]);

  Routine duplicate(String id) {
    final source = byId(id)!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final copy = Routine(
      id: newId(),
      name: '${source.name} copy',
      createdAtMs: now,
      updatedAtMs: now,
      rounds: source.rounds,
      shuffle: source.shuffle,
      steps: [
        for (final s in source.steps)
          RoutineStep(
            id: newId(),
            trackId: s.trackId,
            loopId: s.loopId,
            repeats: s.repeats,
          ),
      ],
    );
    _commit([copy, ...state]);
    return copy;
  }

  /// Removes steps that point at a deleted track.
  void purgeTrack(String trackId) => _purge((s) => s.trackId == trackId);

  /// Removes steps that point at a deleted loop.
  void purgeLoop(String trackId, String loopId) =>
      _purge((s) => s.trackId == trackId && s.loopId == loopId);

  /// How many routines use [loopId] (to warn before deleting it).
  int usageOfLoop(String trackId, String loopId) => state
      .where((r) => r.steps.any((s) => s.trackId == trackId && s.loopId == loopId))
      .length;

  void _purge(bool Function(RoutineStep) shouldRemove) {
    var changed = false;
    final next = [
      for (final routine in state)
        () {
          final kept = [
            for (final s in routine.steps)
              if (!shouldRemove(s)) s,
          ];
          if (kept.length == routine.steps.length) return routine;
          changed = true;
          return routine.copyWith(steps: kept);
        }(),
    ];
    if (changed) _commit(next);
  }
}

final routinesProvider =
    NotifierProvider<RoutinesNotifier, List<Routine>>(RoutinesNotifier.new);

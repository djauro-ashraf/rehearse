import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/routine.dart';
import '../domain/track.dart';
import '../engine/routine_runner.dart';
import 'app_providers.dart';
import 'library_notifier.dart';

/// What the routine player screen shows.
final class RoutineSession {
  const RoutineSession({
    this.name = '',
    this.routineId,
    this.runner = const RunnerState(),
  });

  final String name;

  /// Null for unsaved, one-tap routines such as "play all loops".
  final String? routineId;
  final RunnerState runner;

  RoutineSession copyWith({RunnerState? runner}) => RoutineSession(
        name: name,
        routineId: routineId,
        runner: runner ?? this.runner,
      );
}

class RoutineController extends Notifier<RoutineSession> {
  late RoutineRunner _runner;

  @override
  RoutineSession build() {
    final engine = ref.watch(engineProvider);
    final storage = ref.read(audioStorageProvider);
    _runner = RoutineRunner(
      engine: engine,
      pathFor: (track) => storage.pathFor(track.fileName),
    );
    final subscription =
        _runner.states.listen((r) => state = state.copyWith(runner: r));
    ref.onDispose(() {
      subscription.cancel();
      _runner.dispose();
    });
    return const RoutineSession();
  }

  /// Starts a saved routine. Returns false if none of its steps can play.
  Future<bool> start(Routine routine) async {
    final resolved = resolveRoutine(routine, ref.read(libraryProvider));
    if (resolved.steps.isEmpty) return false;
    state = RoutineSession(name: routine.name, routineId: routine.id);
    await _runner.start(
      resolved.steps,
      rounds: routine.rounds,
      shuffle: routine.shuffle,
    );
    return true;
  }

  /// One tap: play every saved loop of [track] in order.
  Future<bool> startAllLoops(Track track, {int repeats = 3}) async {
    final steps = RoutineRunner.stepsForAllLoops(track, repeats: repeats);
    if (steps.isEmpty) return false;
    state = RoutineSession(name: track.title);
    await _runner.start(steps);
    return true;
  }

  Future<void> next() => _runner.next();

  Future<void> previous() => _runner.previous();

  Future<void> goTo(int index) => _runner.goTo(index);

  Future<void> stop() => _runner.stop();
}

final routineControllerProvider =
    NotifierProvider<RoutineController, RoutineSession>(RoutineController.new);

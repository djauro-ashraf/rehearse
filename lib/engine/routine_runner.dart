import 'dart:async';
import 'dart:math' as math;

import '../domain/gap.dart';
import '../domain/loop.dart';
import '../domain/loop_rules.dart';
import '../domain/routine.dart';
import '../domain/track.dart';
import 'drill_engine.dart';
import 'engine_state.dart';

/// A routine step joined with the track and loop it points at.
final class ResolvedStep {
  const ResolvedStep({required this.step, required this.track, this.loop});

  final RoutineStep step;
  final Track track;

  /// Null means "the whole track".
  final Loop? loop;

  int get startMs => loop?.startMs ?? 0;
  int get endMs => loop?.endMs ?? track.durationMs;
  double get speed => loop?.speed ?? 1.0;
  double get pitch => loop?.pitch ?? 0.0;
  Gap get gap => loop?.gap ?? const Gap.none();
  String get label => loop?.name ?? 'Whole track';

  /// Rough real-time length of the step including gaps.
  int get estimatedMs {
    final perPass = ((endMs - startMs) / speed).round();
    final gapMs = gap.resolveMs(regionMs: endMs - startMs, speed: speed);
    final repeats = step.repeats == 0 ? 1 : step.repeats;
    return (perPass + gapMs) * repeats + step.pauseAfterMs;
  }
}

/// Joins a routine's steps with live tracks/loops. Steps whose track or loop
/// no longer exists are dropped (and counted in [missing]).
({List<ResolvedStep> steps, int missing}) resolveRoutine(
  Routine routine,
  List<Track> tracks,
) {
  final byId = {for (final t in tracks) t.id: t};
  final steps = <ResolvedStep>[];
  var missing = 0;
  for (final step in routine.steps) {
    final track = byId[step.trackId];
    final loop = track?.loopById(step.loopId);
    if (track == null || (step.loopId != null && loop == null)) {
      missing++;
      continue;
    }
    steps.add(ResolvedStep(step: step, track: track, loop: loop));
  }
  return (steps: steps, missing: missing);
}

enum RunnerStatus { idle, running, finished }

final class RunnerState {
  const RunnerState({
    this.status = RunnerStatus.idle,
    this.steps = const [],
    this.index = 0,
    this.round = 1,
    this.rounds = 1,
  });

  final RunnerStatus status;
  final List<ResolvedStep> steps;
  final int index;
  final int round;

  /// 0 means "until stopped".
  final int rounds;

  bool get isActive => status == RunnerStatus.running;
  ResolvedStep? get current =>
      index >= 0 && index < steps.length ? steps[index] : null;

  RunnerState copyWith({
    RunnerStatus? status,
    List<ResolvedStep>? steps,
    int? index,
    int? round,
    int? rounds,
  }) =>
      RunnerState(
        status: status ?? this.status,
        steps: steps ?? this.steps,
        index: index ?? this.index,
        round: round ?? this.round,
        rounds: rounds ?? this.rounds,
      );
}

/// Walks a [DrillEngine] through a list of steps, hands-free: each step plays
/// its loop the requested number of times, then the next step begins.
class RoutineRunner {
  RoutineRunner({
    required this._engine,
    required this._pathFor,
    math.Random? random,
  }) : _random = random ?? math.Random() {
    _eventSub = _engine.events.listen(_onEvent);
  }

  final DrillEngine _engine;
  final String Function(Track track) _pathFor;
  final math.Random _random;
  late final StreamSubscription<EngineEvent> _eventSub;

  final StreamController<RunnerState> _states =
      StreamController<RunnerState>.broadcast();
  RunnerState _state = const RunnerState();
  List<ResolvedStep> _source = const [];
  bool _shuffle = false;
  int _token = 0;

  RunnerState get state => _state;
  Stream<RunnerState> get states => _states.stream;

  Future<void> start(
    List<ResolvedStep> steps, {
    int rounds = 1,
    bool shuffle = false,
    int startIndex = 0,
  }) async {
    if (steps.isEmpty) return;
    _source = steps;
    _shuffle = shuffle;
    final ordered = _ordered();
    _emit(RunnerState(
      status: RunnerStatus.running,
      steps: ordered,
      index: startIndex.clamp(0, ordered.length - 1),
      rounds: rounds,
    ));
    _engine.setSkipHandlers(next: next, previous: previous);
    await _engine.setTrainer(null);
    await _enter(_state.index);
  }

  /// Jumps to the next step (or round / finish), as if this one had ended.
  Future<void> next() async {
    if (!_state.isActive) return;
    await _advance();
  }

  Future<void> previous() async {
    if (!_state.isActive) return;
    final target = _state.index > 0 ? _state.index - 1 : 0;
    _emit(_state.copyWith(index: target));
    await _enter(target);
  }

  /// Jumps straight to step [index] (e.g. tapped in the list).
  Future<void> goTo(int index) async {
    if (!_state.isActive || index < 0 || index >= _state.steps.length) return;
    _emit(_state.copyWith(index: index));
    await _enter(index);
  }

  Future<void> stop() async {
    if (_state.status == RunnerStatus.idle) return;
    _token++;
    _engine.setSkipHandlers();
    _emit(const RunnerState());
    await _engine.pause();
  }

  List<ResolvedStep> _ordered() =>
      _shuffle ? ([..._source]..shuffle(_random)) : _source;

  void _onEvent(EngineEvent event) {
    if (!_state.isActive) return;
    switch (event) {
      case EngineEvent.targetReached:
        final pause = _state.current?.step.pauseAfterMs ?? 0;
        if (pause > 0) {
          _engine.hold(pause);
        } else {
          unawaited(_proceed());
        }
      case EngineEvent.holdEnded:
        unawaited(_proceed());
      case EngineEvent.trackEnded:
        break;
    }
  }

  /// Runs the finished step's "what next" rule.
  Future<void> _proceed() async {
    final current = _state.current;
    if (current == null || !_state.isActive) return;
    switch (current.step.next.kind) {
      case StepNextKind.next:
        await _advance();
      case StepNextKind.stop:
        await _finish();
      case StepNextKind.shuffle:
        final others = [
          for (var i = 0; i < _state.steps.length; i++)
            if (i != _state.index) i,
        ];
        if (others.isEmpty) {
          await _finish();
        } else {
          await _jump(others[_random.nextInt(others.length)]);
        }
      case StepNextKind.goTo:
        final found = _state.steps
            .indexWhere((s) => s.step.id == current.step.next.stepId);
        final target = found < 0 ? null : found;
        // A target that no longer exists falls back to "next step".
        if (target == null) {
          await _advance();
        } else {
          await _jump(target);
        }
    }
  }

  Future<void> _jump(int index) async {
    _emit(_state.copyWith(index: index));
    await _enter(index);
  }

  Future<void> _finish() async {
    _token++;
    _engine.setSkipHandlers();
    _emit(_state.copyWith(status: RunnerStatus.finished));
    await _engine.pause();
  }

  Future<void> _advance() async {
    final nextIndex = _state.index + 1;
    if (nextIndex < _state.steps.length) {
      _emit(_state.copyWith(index: nextIndex));
      await _enter(nextIndex);
      return;
    }
    final another = _state.rounds == 0 || _state.round < _state.rounds;
    if (another) {
      _emit(_state.copyWith(
        steps: _ordered(),
        index: 0,
        round: _state.round + 1,
      ));
      await _enter(0);
      return;
    }
    await _finish();
  }

  Future<void> _enter(int index, {int failures = 0}) async {
    final token = ++_token;
    final step = _state.steps[index];
    final sameTrack = _engine.state.trackId == step.track.id &&
        _engine.state.error == null;
    if (sameTrack) {
      await _engine.applyLoop(
        startMs: step.startMs,
        endMs: step.endMs,
        speed: step.speed,
        pitch: step.pitch,
        repeats: step.step.repeats,
        gap: step.gap,
      );
    } else {
      await _engine.load(
        trackId: step.track.id,
        path: _pathFor(step.track),
        title: step.track.title,
        durationHintMs: step.track.durationMs,
        startMs: step.startMs,
        speed: step.speed,
        pitch: step.pitch,
        loopStartMs: step.startMs,
        loopEndMs: step.endMs,
        loopOn: true,
        repeats: step.step.repeats,
        gap: step.gap,
      );
    }
    if (token != _token) return;
    if (_engine.state.error != null) {
      // Unplayable step (file missing): skip it, but never spin forever.
      if (failures + 1 >= _state.steps.length) {
        await stop();
        return;
      }
      final nextIndex = (index + 1) % _state.steps.length;
      _emit(_state.copyWith(index: nextIndex));
      await _enter(nextIndex, failures: failures + 1);
      return;
    }
    await _engine.play();
  }

  void _emit(RunnerState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  /// Builds an unsaved routine that plays every saved loop of [track] in
  /// order, [repeats] times each.
  static List<ResolvedStep> stepsForAllLoops(Track track, {int repeats = 3}) {
    final loops = [...track.loops]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return [
      for (var i = 0; i < loops.length; i++)
        ResolvedStep(
          step: RoutineStep(
            id: 'adhoc$i',
            trackId: track.id,
            loopId: loops[i].id,
            repeats: repeats.clamp(1, LoopRules.maxRepeats),
          ),
          track: track,
          loop: loops[i],
        ),
    ];
  }

  Future<void> dispose() async {
    _token++;
    await _eventSub.cancel();
    await _states.close();
  }
}

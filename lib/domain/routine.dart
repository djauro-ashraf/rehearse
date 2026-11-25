import '../core/json.dart';
import 'loop_rules.dart';

enum StepNextKind { next, stop, shuffle, goTo }

/// What a routine does once a step has played all its repeats.
final class StepNext {
  const StepNext.next()
      : kind = StepNextKind.next,
        stepId = null;

  const StepNext.stop()
      : kind = StepNextKind.stop,
        stepId = null;

  /// A random *other* step.
  const StepNext.shuffle()
      : kind = StepNextKind.shuffle,
        stepId = null;

  const StepNext.goTo(String this.stepId) : kind = StepNextKind.goTo;

  factory StepNext.fromJson(Object? json) {
    final map = asMap(json);
    final id = asStringOrNull(map['stepId']);
    return switch (asString(map['kind'])) {
      'stop' => const StepNext.stop(),
      'shuffle' => const StepNext.shuffle(),
      'goTo' when id != null => StepNext.goTo(id),
      _ => const StepNext.next(),
    };
  }

  final StepNextKind kind;
  final String? stepId;

  Map<String, Object?> toJson() => {'kind': kind.name, 'stepId': stepId};

  @override
  bool operator ==(Object other) =>
      other is StepNext && other.kind == kind && other.stepId == stepId;

  @override
  int get hashCode => Object.hash(kind, stepId);
}

/// One step of a [Routine]: play a saved loop (or a whole track when
/// [loopId] is null) a number of times, optionally pause, then continue
/// according to [next].
final class RoutineStep {
  const RoutineStep({
    required this.id,
    required this.trackId,
    this.loopId,
    this.repeats = 3,
    this.pauseAfterMs = 0,
    this.next = const StepNext.next(),
  });

  factory RoutineStep.fromJson(Map<String, Object?> json) => RoutineStep(
        id: asString(json['id']),
        trackId: asString(json['trackId']),
        loopId: asStringOrNull(json['loopId']),
        repeats: asInt(json['repeats'], 3).clamp(0, LoopRules.maxRepeats),
        pauseAfterMs:
            asInt(json['pauseAfterMs']).clamp(0, LoopRules.maxStepPauseMs),
        next: StepNext.fromJson(json['next']),
      );

  final String id;
  final String trackId;
  final String? loopId;

  /// 0 means "until I move on myself".
  final int repeats;

  /// Silence after the last repeat, before the next action runs.
  final int pauseAfterMs;
  final StepNext next;

  RoutineStep copyWith({int? repeats, int? pauseAfterMs, StepNext? next}) =>
      RoutineStep(
        id: id,
        trackId: trackId,
        loopId: loopId,
        repeats: repeats ?? this.repeats,
        pauseAfterMs: pauseAfterMs ?? this.pauseAfterMs,
        next: next ?? this.next,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'trackId': trackId,
        'loopId': loopId,
        'repeats': repeats,
        'pauseAfterMs': pauseAfterMs,
        'next': next.toJson(),
      };
}

/// An ordered practice plan that plays hands-free.
final class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.steps = const [],
    this.rounds = 1,
    this.shuffle = false,
  });

  factory Routine.fromJson(Map<String, Object?> json) => Routine(
        id: asString(json['id']),
        name: asString(json['name'], 'Routine'),
        createdAtMs: asInt(json['createdAtMs']),
        updatedAtMs: asInt(json['updatedAtMs']),
        steps: parseList(json['steps'], RoutineStep.fromJson),
        rounds: asInt(json['rounds'], 1).clamp(0, 99),
        shuffle: asBool(json['shuffle']),
      );

  final String id;
  final String name;
  final int createdAtMs;
  final int updatedAtMs;
  final List<RoutineStep> steps;

  /// How many times to run the whole routine; 0 means until stopped.
  final int rounds;
  final bool shuffle;

  Routine copyWith({
    String? name,
    int? updatedAtMs,
    List<RoutineStep>? steps,
    int? rounds,
    bool? shuffle,
  }) =>
      Routine(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        steps: steps ?? this.steps,
        rounds: rounds ?? this.rounds,
        shuffle: shuffle ?? this.shuffle,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'steps': [for (final s in steps) s.toJson()],
        'rounds': rounds,
        'shuffle': shuffle,
      };
}

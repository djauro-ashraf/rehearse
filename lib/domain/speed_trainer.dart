import '../core/json.dart';
import 'loop_rules.dart';

/// Gradually raises the playback speed while a loop repeats: start slow, add
/// [step] every [everyPasses] passes, stop at [target].
final class SpeedTrainer {
  const SpeedTrainer({
    this.enabled = false,
    this.start = 0.6,
    this.target = 1.0,
    this.step = 0.05,
    this.everyPasses = 3,
  });

  factory SpeedTrainer.fromJson(Object? json) {
    final map = asMap(json);
    return SpeedTrainer(
      enabled: asBool(map['enabled']),
      start: LoopRules.clampSpeed(asDouble(map['start'], 0.6)),
      target: LoopRules.clampSpeed(asDouble(map['target'], 1.0)),
      step: asDouble(map['step'], 0.05).clamp(0.05, 0.5),
      everyPasses: asInt(map['everyPasses'], 3).clamp(1, 20),
    );
  }

  final bool enabled;
  final double start;
  final double target;
  final double step;
  final int everyPasses;

  /// The speed to use after [pass] completed passes, given the [current] one.
  double speedAfterPass(int pass, double current) {
    if (!enabled || pass <= 0 || pass % everyPasses != 0) return current;
    if (current >= target) return current;
    final next = LoopRules.clampSpeed(current + step);
    return next > target ? target : next;
  }

  SpeedTrainer copyWith({
    bool? enabled,
    double? start,
    double? target,
    double? step,
    int? everyPasses,
  }) =>
      SpeedTrainer(
        enabled: enabled ?? this.enabled,
        start: start ?? this.start,
        target: target ?? this.target,
        step: step ?? this.step,
        everyPasses: everyPasses ?? this.everyPasses,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'start': start,
        'target': target,
        'step': step,
        'everyPasses': everyPasses,
      };

  @override
  bool operator ==(Object other) =>
      other is SpeedTrainer &&
      other.enabled == enabled &&
      other.start == start &&
      other.target == target &&
      other.step == step &&
      other.everyPasses == everyPasses;

  @override
  int get hashCode => Object.hash(enabled, start, target, step, everyPasses);
}

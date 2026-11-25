import '../core/json.dart';
import 'gap.dart';
import 'loop_rules.dart';

/// A saved passage of one track: where it starts and ends, and how you like to
/// drill it (speed, pitch, repeats, gap).
final class Loop {
  const Loop({
    required this.id,
    required this.name,
    required this.startMs,
    required this.endMs,
    required this.createdAtMs,
    this.speed = 1.0,
    this.pitch = 0.0,
    this.repeats = 0,
    this.gap = const Gap.none(),
  });

  factory Loop.fromJson(Map<String, Object?> json) {
    final start = asInt(json['startMs']).clamp(0, 1 << 40);
    final end = asInt(json['endMs']);
    return Loop(
      id: asString(json['id']),
      name: asString(json['name'], 'Loop'),
      startMs: start,
      endMs: end <= start ? start + LoopRules.minLoopMs : end,
      createdAtMs: asInt(json['createdAtMs']),
      speed: LoopRules.clampSpeed(asDouble(json['speed'], 1.0)),
      pitch: LoopRules.clampPitch(asDouble(json['pitch'])),
      repeats: LoopRules.clampRepeats(asInt(json['repeats'])),
      gap: Gap.fromJson(json['gap']),
    );
  }

  final String id;
  final String name;
  final int startMs;
  final int endMs;
  final int createdAtMs;
  final double speed;
  final double pitch;

  /// How many passes to play before stopping; 0 means "until I stop it".
  final int repeats;
  final Gap gap;

  int get lengthMs => endMs - startMs;

  Loop copyWith({
    String? name,
    int? startMs,
    int? endMs,
    double? speed,
    double? pitch,
    int? repeats,
    Gap? gap,
  }) =>
      Loop(
        id: id,
        name: name ?? this.name,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        createdAtMs: createdAtMs,
        speed: speed ?? this.speed,
        pitch: pitch ?? this.pitch,
        repeats: repeats ?? this.repeats,
        gap: gap ?? this.gap,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'startMs': startMs,
        'endMs': endMs,
        'createdAtMs': createdAtMs,
        'speed': speed,
        'pitch': pitch,
        'repeats': repeats,
        'gap': gap.toJson(),
      };
}

import '../core/json.dart';
import 'loop_rules.dart';

enum GapKind { none, fixed, clip }

/// The silence inserted after every pass of a loop.
///
/// * [Gap.none]  – loop straight back to A.
/// * [Gap.fixed] – wait a fixed time.
/// * [Gap.clip]  – wait as long as the loop itself lasts, so the learner can
///   repeat the phrase out loud ("your turn" / shadowing).
final class Gap {
  const Gap.none()
      : kind = GapKind.none,
        ms = 0;

  const Gap.fixed(this.ms) : kind = GapKind.fixed;

  const Gap.clip()
      : kind = GapKind.clip,
        ms = 0;

  factory Gap.fromJson(Object? json) {
    final map = asMap(json);
    return switch (asString(map['type'])) {
      'fixed' => Gap.fixed(asInt(map['ms']).clamp(100, LoopRules.maxGapMs)),
      'clip' => const Gap.clip(),
      _ => const Gap.none(),
    };
  }

  final GapKind kind;
  final int ms;

  bool get isNone => kind == GapKind.none;

  /// Real-time length of the gap for a region of [regionMs] audio played at
  /// [speed].
  int resolveMs({required int regionMs, required double speed}) {
    return switch (kind) {
      GapKind.none => 0,
      GapKind.fixed => ms,
      GapKind.clip => (regionMs / (speed <= 0 ? 1 : speed))
          .round()
          .clamp(0, LoopRules.maxGapMs),
    };
  }

  Map<String, Object?> toJson() => switch (kind) {
        GapKind.none => {'type': 'none'},
        GapKind.fixed => {'type': 'fixed', 'ms': ms},
        GapKind.clip => {'type': 'clip'},
      };

  @override
  bool operator ==(Object other) =>
      other is Gap && other.kind == kind && other.ms == ms;

  @override
  int get hashCode => Object.hash(kind, ms);
}

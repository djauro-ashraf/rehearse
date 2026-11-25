/// Every limit and sanitising rule for loops lives here, so the UI, the engine
/// and imported data can never disagree about what a valid loop is.
abstract final class LoopRules {
  static const int minLoopMs = 100;
  static const int defaultLoopMs = 10000;
  static const int maxRepeats = 999;
  static const int maxGapMs = 60000;

  /// Longest pause between two routine steps (10 minutes).
  static const int maxStepPauseMs = 600000;

  static const double minSpeed = 0.25;
  static const double maxSpeed = 3.0;
  static const double speedStep = 0.05;
  static const double minPitch = -12;
  static const double maxPitch = 12;

  static const int minPreviewMs = 1000;
  static const int maxPreviewMs = 15000;

  /// Clamps to the supported range and snaps to [speedStep].
  static double clampSpeed(double speed) {
    final clamped = speed.clamp(minSpeed, maxSpeed);
    return (clamped * 20).round() / 20;
  }

  /// Whole semitones only: fine-grained pitch is rarely useful for practice.
  static double clampPitch(double semitones) =>
      semitones.clamp(minPitch, maxPitch).roundToDouble();

  static int clampRepeats(int repeats) => repeats.clamp(0, maxRepeats);

  static int clampPreview(int ms) => ms.clamp(minPreviewMs, maxPreviewMs);

  /// Returns a valid `(start, end)` inside `[0, durationMs]`, keeping the
  /// requested [startMs] whenever possible. Null if the track is too short.
  static (int, int)? region(int startMs, int endMs, int durationMs) {
    if (durationMs < minLoopMs) return null;
    final start = startMs.clamp(0, durationMs - minLoopMs);
    final end = endMs.clamp(start + minLoopMs, durationMs);
    return (start, end);
  }

  /// A fresh loop that begins at [positionMs] and runs [defaultLoopMs].
  static (int, int)? regionFrom(int positionMs, int durationMs) =>
      region(positionMs, positionMs + defaultLoopMs, durationMs);

  /// A fresh loop that ends at [positionMs] and runs [defaultLoopMs] back.
  static (int, int)? regionEndingAt(int positionMs, int durationMs) {
    final end = positionMs.clamp(minLoopMs, durationMs);
    return region(end - defaultLoopMs, end, durationMs);
  }

  /// Moves A while keeping B (and at least [minLoopMs] between them).
  static int clampStart(int startMs, int endMs) {
    final max = endMs - minLoopMs;
    return startMs.clamp(0, max < 0 ? 0 : max);
  }

  /// Moves B while keeping A (and never past the end of the track).
  static int clampEnd(int endMs, int startMs, int durationMs) {
    final min = startMs + minLoopMs;
    return endMs.clamp(min, durationMs < min ? min : durationMs);
  }

  /// Where a "B preview" starts: a short lead-in before B. When the lead-in
  /// is as long as the loop itself (or longer) previewing would feel like a
  /// broken loop, so there is no preview (null) and A/B simply stay put.
  static int? previewStart(int startMs, int endMs, int previewMs) {
    if (previewMs >= endMs - startMs) return null;
    return endMs - previewMs;
  }
}

import '../domain/gap.dart';
import '../domain/speed_trainer.dart';

/// Things the engine announces that aren't plain state changes.
enum EngineEvent {
  /// The loop played its requested number of passes.
  targetReached,

  /// A track without an active loop played to its end.
  trackEnded,

  /// A pause between routine steps (see `DrillEngine.hold`) has run out.
  holdEnded,
}

/// An immutable snapshot of everything the UI needs to draw the player.
/// (The playhead position is deliberately not part of it: it changes 30 times
/// a second and has its own stream.)
final class EngineState {
  const EngineState({
    this.trackId,
    this.title = '',
    this.durationMs = 0,
    this.loading = false,
    this.playing = false,
    this.inGap = false,
    this.holding = false,
    this.gapMs = 0,
    this.speed = 1.0,
    this.pitch = 0.0,
    this.loopStartMs,
    this.loopEndMs,
    this.loopOn = false,
    this.pass = 0,
    this.repeats = 0,
    this.gap = const Gap.none(),
    this.trainer,
    this.targetReached = false,
    this.hasNext = false,
    this.hasPrevious = false,
    this.error,
  });

  final String? trackId;
  final String title;
  final int durationMs;
  final bool loading;

  /// True while audio plays *or* while waiting out a [Gap] (the user's turn).
  final bool playing;
  final bool inGap;

  /// Waiting between two routine steps (also counts as [playing]).
  final bool holding;
  final int gapMs;
  final double speed;
  final double pitch;
  final int? loopStartMs;
  final int? loopEndMs;
  final bool loopOn;

  /// Completed passes of the current loop.
  final int pass;

  /// Passes to play before stopping; 0 means forever.
  final int repeats;
  final Gap gap;
  final SpeedTrainer? trainer;

  /// The loop finished its requested passes and is parked at A.
  final bool targetReached;
  final bool hasNext;
  final bool hasPrevious;
  final String? error;

  bool get hasTrack => trackId != null;
  bool get hasLoop => loopStartMs != null && loopEndMs != null;
  int get loopLengthMs => hasLoop ? loopEndMs! - loopStartMs! : 0;

  EngineState copyWith({
    int? durationMs,
    bool? loading,
    bool? playing,
    bool? inGap,
    bool? holding,
    int? gapMs,
    double? speed,
    double? pitch,
    int? loopStartMs,
    int? loopEndMs,
    bool? loopOn,
    int? pass,
    int? repeats,
    Gap? gap,
    SpeedTrainer? trainer,
    bool? targetReached,
    bool? hasNext,
    bool? hasPrevious,
    String? error,
    bool clearLoop = false,
    bool clearTrainer = false,
    bool clearError = false,
  }) =>
      EngineState(
        trackId: trackId,
        title: title,
        durationMs: durationMs ?? this.durationMs,
        loading: loading ?? this.loading,
        playing: playing ?? this.playing,
        inGap: inGap ?? this.inGap,
        holding: holding ?? this.holding,
        gapMs: gapMs ?? this.gapMs,
        speed: speed ?? this.speed,
        pitch: pitch ?? this.pitch,
        loopStartMs: clearLoop ? null : loopStartMs ?? this.loopStartMs,
        loopEndMs: clearLoop ? null : loopEndMs ?? this.loopEndMs,
        loopOn: clearLoop ? false : loopOn ?? this.loopOn,
        pass: pass ?? this.pass,
        repeats: repeats ?? this.repeats,
        gap: gap ?? this.gap,
        trainer: clearTrainer ? null : trainer ?? this.trainer,
        targetReached: targetReached ?? this.targetReached,
        hasNext: hasNext ?? this.hasNext,
        hasPrevious: hasPrevious ?? this.hasPrevious,
        error: clearError ? null : error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      other is EngineState &&
      other.trackId == trackId &&
      other.title == title &&
      other.durationMs == durationMs &&
      other.loading == loading &&
      other.playing == playing &&
      other.inGap == inGap &&
      other.holding == holding &&
      other.gapMs == gapMs &&
      other.speed == speed &&
      other.pitch == pitch &&
      other.loopStartMs == loopStartMs &&
      other.loopEndMs == loopEndMs &&
      other.loopOn == loopOn &&
      other.pass == pass &&
      other.repeats == repeats &&
      other.gap == gap &&
      other.trainer == trainer &&
      other.targetReached == targetReached &&
      other.hasNext == hasNext &&
      other.hasPrevious == hasPrevious &&
      other.error == error;

  @override
  int get hashCode => Object.hashAll([
        trackId,
        title,
        durationMs,
        loading,
        playing,
        inGap,
        holding,
        gapMs,
        speed,
        pitch,
        loopStartMs,
        loopEndMs,
        loopOn,
        pass,
        repeats,
        gap,
        trainer,
        targetReached,
        hasNext,
        hasPrevious,
        error,
      ]);
}

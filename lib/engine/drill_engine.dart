import 'dart:async';
import 'dart:math' as math;

import '../domain/gap.dart';
import '../domain/loop_rules.dart';
import '../domain/speed_trainer.dart';
import 'audio_backend.dart';
import 'engine_state.dart';

/// Creates a one-shot timer. Injected so tests can control time.
typedef TimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

typedef SkipHandler = Future<void> Function();

/// The heart of the app: plays one track and keeps it inside an A–B loop,
/// counts passes, inserts "your turn" gaps, and ramps speed.
///
/// It owns no UI and knows nothing about files, storage or Flutter. Screens
/// and the routine runner just tell it what to drill and listen to [states].
class DrillEngine {
  DrillEngine(this._backend, {TimerFactory? timers})
      : _timers = timers ?? Timer.new {
    _subscriptions
      ..add(_backend.positionStream.listen(_onPosition))
      ..add(_backend.playingStream.listen(_onBackendPlaying))
      ..add(_backend.completedStream.listen((_) => _onCompleted()))
      ..add(_backend.interruptions.listen((_) => _onInterrupted()));
  }

  /// How early (in real time) we jump back to A, to hide seek latency.
  static const int _leadMs = 25;

  /// A seek that hasn't visibly landed after this long is retried.
  static const int _wrapRetryMs = 400;

  final AudioBackend _backend;
  final TimerFactory _timers;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  final StreamController<EngineState> _states =
      StreamController<EngineState>.broadcast();
  final StreamController<int> _positions = StreamController<int>.broadcast();
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();

  EngineState _state = const EngineState();
  int _posMs = 0;
  bool _backendPlaying = false;
  bool _inGap = false;
  bool _holding = false;

  /// A one-off "play just this range, then pause" (stamping, previews). While
  /// it is active the loop guard stands aside.
  (int, int)? _range;

  /// True while a wrap-around (or end-of-target) is being carried out, so the
  /// position stream can't trigger it twice.
  bool _busy = false;
  int _busySince = 0;
  Timer? _gapTimer;
  int _loadToken = 0;
  bool _disposed = false;

  SkipHandler? _onNext;
  SkipHandler? _onPrevious;

  EngineState get state => _state;
  Stream<EngineState> get states => _states.stream;
  Stream<int> get positions => _positions.stream;
  Stream<EngineEvent> get events => _events.stream;
  int get positionMs => _posMs;

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Opens a track and restores the given practice setup.
  Future<void> load({
    required String trackId,
    required String path,
    required String title,
    int? durationHintMs,
    int startMs = 0,
    double speed = 1.0,
    double pitch = 0.0,
    int? loopStartMs,
    int? loopEndMs,
    bool loopOn = false,
    int repeats = 0,
    Gap gap = const Gap.none(),
  }) async {
    final token = ++_loadToken;
    _cancelGap();
    await _safe(_backend.pause);
    final sp = LoopRules.clampSpeed(speed);
    final pt = LoopRules.clampPitch(pitch);
    _posMs = 0;
    _setState(EngineState(
      trackId: trackId,
      title: title,
      durationMs: durationHintMs ?? 0,
      loading: true,
      speed: sp,
      pitch: pt,
      repeats: LoopRules.clampRepeats(repeats),
      gap: gap,
      trainer: _state.trainer,
    ));
    try {
      final loaded = await _backend.load(path);
      if (token != _loadToken) return;
      final duration = loaded?.inMilliseconds ?? durationHintMs ?? 0;
      await _safe(() => _backend.setSpeed(sp));
      await _safe(() => _backend.setPitchSemitones(pt));

      // A remembered loop that lies (almost) outside the file is dropped
      // rather than squashed into its last fraction of a second.
      final region = loopStartMs != null &&
              loopEndMs != null &&
              loopStartMs < duration - LoopRules.minLoopMs
          ? LoopRules.region(loopStartMs, loopEndMs, duration)
          : null;
      final lastMs = math.max(0, duration - 1);
      var start = startMs.clamp(0, lastMs);
      if (region != null && loopOn && (start < region.$1 || start >= region.$2)) {
        start = region.$1;
      }
      await _backend.seek(Duration(milliseconds: start));
      if (token != _loadToken) return;
      _emitPosition(start);
      _setState(_state.copyWith(
        durationMs: duration,
        loading: false,
        loopStartMs: region?.$1,
        loopEndMs: region?.$2,
        loopOn: region != null && loopOn,
      ));
    } catch (_) {
      if (token != _loadToken) return;
      _setState(_state.copyWith(
        loading: false,
        error: 'This audio file could not be opened.',
      ));
    }
  }

  /// Stops playback and forgets the current track (e.g. it was deleted).
  Future<void> unload() async {
    _loadToken++;
    _cancelGap();
    await _safe(_backend.stop);
    _emitPosition(0);
    _setState(EngineState(trainer: _state.trainer));
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  Future<void> play() async {
    if (!_state.hasTrack || _state.loading || _state.error != null) return;
    if (_holding) {
      // Pressing play during a pause between steps skips the wait.
      _gapTimer?.cancel();
      _endHold();
      return;
    }
    _cancelGap();
    if (_state.targetReached) {
      // The last drill finished; pressing play starts a fresh one.
      _setState(_state.copyWith(pass: 0, targetReached: false));
      final trainer = _state.trainer;
      if (trainer != null && trainer.enabled) await setSpeed(trainer.start);
    }
    final a = _state.loopStartMs;
    final b = _state.loopEndMs;
    if (_state.loopOn && a != null && b != null) {
      if (_posMs < a || _posMs >= b - _audioLead()) await _seek(a);
    } else if (_state.durationMs > 0 && _posMs >= _state.durationMs - 100) {
      await _seek(0);
    }
    unawaited(_backend.play());
  }

  Future<void> pause() async {
    _cancelGap();
    await _safe(_backend.pause);
    _setState(_state);
  }

  Future<void> toggle() => _state.playing ? pause() : play();

  /// Seeks to an absolute position. While a loop is on, the playhead stays
  /// inside it (turn the loop off to roam freely).
  Future<void> seekTo(int ms) async {
    if (!_state.hasTrack || _state.loading) return;
    final a = _state.loopStartMs;
    final b = _state.loopEndMs;
    final lastMs = math.max(0, _state.durationMs);
    final int target = _state.loopOn && a != null && b != null
        ? ms.clamp(a, b - 1)
        : ms.clamp(0, lastMs);
    final resume = _inGap;
    _cancelGap();
    await _seek(target);
    if (resume) unawaited(_backend.play());
  }

  Future<void> skip(int deltaMs) => seekTo(_posMs + deltaMs);

  /// Plays [startMs]–[endMs] once and pauses at the end, whatever the loop
  /// settings are. Any seek, pause or play cancels it.
  Future<void> playRange(int startMs, int endMs) async {
    if (!_state.hasTrack || _state.loading || _state.error != null) return;
    final duration = _state.durationMs;
    final start = startMs.clamp(0, duration);
    final end = endMs.clamp(start + 1, duration < start + 1 ? start + 1 : duration);
    _cancelGap();
    _range = (start, end);
    await _seek(start);
    unawaited(_backend.play());
  }

  /// Waits [ms] (counted as "playing", so the system keeps us alive) and then
  /// emits [EngineEvent.holdEnded]. Used for the pause between routine steps.
  void hold(int ms) {
    _cancelGap();
    _holding = true;
    _inGap = true;
    _busy = true;
    _setState(_state.copyWith(gapMs: ms));
    _gapTimer = _timers(Duration(milliseconds: ms), _endHold);
  }

  // ── Loop ──────────────────────────────────────────────────────────────────

  /// Moves the A–B region without touching the playhead (cheap enough to call
  /// on every drag frame). Passes restart because it is a new passage.
  void setLoopRegion(int startMs, int endMs, {bool? loopOn}) {
    final region = LoopRules.region(startMs, endMs, _state.durationMs);
    if (region == null) return;
    final moved =
        region.$1 != _state.loopStartMs || region.$2 != _state.loopEndMs;
    _setState(_state.copyWith(
      loopStartMs: region.$1,
      loopEndMs: region.$2,
      loopOn: loopOn ?? _state.loopOn,
      pass: moved ? 0 : _state.pass,
      targetReached: moved ? false : _state.targetReached,
    ));
  }

  Future<void> setLoopOn(bool on) async {
    if (on && !_state.hasLoop) return;
    if (!on) _cancelGap();
    _setState(_state.copyWith(loopOn: on, pass: 0, targetReached: false));
    final a = _state.loopStartMs;
    final b = _state.loopEndMs;
    if (on && a != null && b != null && (_posMs < a || _posMs >= b)) {
      await _seek(a);
    }
  }

  void clearLoop() {
    _cancelGap();
    _setState(_state.copyWith(clearLoop: true, pass: 0, targetReached: false));
  }

  void resetPasses() =>
      _setState(_state.copyWith(pass: 0, targetReached: false));

  /// Sets up a complete drill in one step (used for saved loops and routine
  /// steps). Clears the speed trainer unless [keepTrainer] is set.
  Future<void> applyLoop({
    required int startMs,
    required int endMs,
    double? speed,
    double? pitch,
    int repeats = 0,
    Gap gap = const Gap.none(),
    bool seekToStart = true,
    bool keepTrainer = false,
  }) async {
    final region = LoopRules.region(startMs, endMs, _state.durationMs);
    if (region == null) return;
    _cancelGap();
    final sp = speed == null ? _state.speed : LoopRules.clampSpeed(speed);
    final pt = pitch == null ? _state.pitch : LoopRules.clampPitch(pitch);
    _setState(_state.copyWith(
      loopStartMs: region.$1,
      loopEndMs: region.$2,
      loopOn: true,
      speed: sp,
      pitch: pt,
      repeats: LoopRules.clampRepeats(repeats),
      gap: gap,
      pass: 0,
      targetReached: false,
      clearTrainer: !keepTrainer,
    ));
    await _safe(() => _backend.setSpeed(sp));
    await _safe(() => _backend.setPitchSemitones(pt));
    if (seekToStart) await _seek(region.$1);
  }

  void setRepeats(int repeats) =>
      _setState(_state.copyWith(repeats: LoopRules.clampRepeats(repeats)));

  void setGap(Gap gap) => _setState(_state.copyWith(gap: gap));

  /// Enables, updates or (with null) removes the speed trainer. When enabled,
  /// the drill restarts at the trainer's starting speed.
  Future<void> setTrainer(SpeedTrainer? trainer) async {
    _setState(_state.copyWith(
      trainer: trainer,
      clearTrainer: trainer == null,
      pass: 0,
      targetReached: false,
    ));
    if (trainer != null && trainer.enabled) await setSpeed(trainer.start);
  }

  // ── Sound ─────────────────────────────────────────────────────────────────

  Future<void> setSpeed(double speed) async {
    final value = LoopRules.clampSpeed(speed);
    _setState(_state.copyWith(speed: value));
    await _safe(() => _backend.setSpeed(value));
  }

  Future<void> setPitch(double semitones) async {
    final value = LoopRules.clampPitch(semitones);
    _setState(_state.copyWith(pitch: value));
    await _safe(() => _backend.setPitchSemitones(value));
  }

  // ── Notification / lock-screen skip buttons ──────────────────────────────

  void setSkipHandlers({SkipHandler? next, SkipHandler? previous}) {
    _onNext = next;
    _onPrevious = previous;
    _setState(_state);
  }

  Future<void> skipNext() async => _onNext?.call();

  Future<void> skipPrevious() async => _onPrevious?.call();

  // ── Internals ─────────────────────────────────────────────────────────────

  int _audioLead() => (_leadMs * _state.speed).round();

  void _onBackendPlaying(bool playing) {
    _backendPlaying = playing;
    _setState(_state);
  }

  void _onPosition(Duration position) {
    _emitPosition(position.inMilliseconds);
    final range = _range;
    if (range != null) {
      if (_backendPlaying && _posMs >= range.$2 - _audioLead()) {
        _range = null;
        unawaited(_finishRange(range.$2));
      }
      return;
    }
    if (!_backendPlaying || _inGap || !_state.loopOn) return;
    final a = _state.loopStartMs;
    final b = _state.loopEndMs;
    if (a == null || b == null) return;

    final threshold = b - _audioLead();
    if (_busy) {
      // Waiting for a seek to land; if it never does, try again.
      final waited = DateTime.now().millisecondsSinceEpoch - _busySince;
      if (_posMs < threshold - 100 || waited < _wrapRetryMs) return;
      _busy = false;
    }
    if (_posMs >= threshold) {
      unawaited(_completePass());
    } else if (_posMs < a - 150) {
      // Region moved past the playhead: pull it back in.
      unawaited(_seek(a));
    }
  }

  Future<void> _completePass({bool fromCompletion = false}) async {
    if (_busy) return;
    final a = _state.loopStartMs;
    final b = _state.loopEndMs;
    if (a == null || b == null) return;
    _busy = true;
    _busySince = DateTime.now().millisecondsSinceEpoch;

    final pass = _state.pass + 1;
    final oldSpeed = _state.speed;
    final newSpeed = _state.trainer?.speedAfterPass(pass, oldSpeed) ?? oldSpeed;
    final done = _state.repeats > 0 && pass >= _state.repeats;
    _setState(_state.copyWith(pass: pass, speed: newSpeed));
    if (newSpeed != oldSpeed) await _safe(() => _backend.setSpeed(newSpeed));

    if (done) {
      await _safe(_backend.pause);
      await _seek(a);
      _busy = false;
      _setState(_state.copyWith(targetReached: true));
      _events.add(EngineEvent.targetReached);
      return;
    }

    final gapMs = _state.gap.resolveMs(regionMs: b - a, speed: newSpeed);
    if (gapMs > 0) {
      _inGap = true;
      _setState(_state.copyWith(gapMs: gapMs));
      await _safe(_backend.pause);
      await _seek(a);
      if (!_inGap) return; // cancelled while pausing
      _gapTimer = _timers(Duration(milliseconds: gapMs), _endGap);
      return;
    }

    await _seek(a);
    _busy = false;
    if (fromCompletion) unawaited(_backend.play());
  }

  Future<void> _finishRange(int endMs) async {
    await _safe(_backend.pause);
    _emitPosition(endMs);
  }

  void _endHold() {
    _gapTimer = null;
    if (!_holding) return;
    _holding = false;
    _inGap = false;
    _busy = false;
    _setState(_state.copyWith(gapMs: 0));
    if (!_events.isClosed) _events.add(EngineEvent.holdEnded);
  }

  void _endGap() {
    _gapTimer = null;
    if (!_inGap) return;
    _inGap = false;
    _busy = false;
    _setState(_state.copyWith(gapMs: 0));
    unawaited(_backend.play());
  }

  void _cancelGap() {
    _gapTimer?.cancel();
    _gapTimer = null;
    _inGap = false;
    _holding = false;
    _range = null;
    _busy = false;
    if (_state.gapMs != 0) _setState(_state.copyWith(gapMs: 0));
  }

  /// Headphones out / a call began. A playing player pauses itself; we also
  /// have to end the silent waits (gaps, holds, one-off ranges), or they
  /// would start the audio again through the speaker a moment later.
  void _onInterrupted() {
    if (_inGap || _holding || _range != null) unawaited(pause());
  }

  void _onCompleted() {
    if (!_state.hasTrack || _state.loading) return;
    if (_range != null) {
      _range = null;
      unawaited(_endOfTrack());
      return;
    }
    if (_state.loopOn && _state.hasLoop) {
      if (!_busy && !_inGap) unawaited(_completePass(fromCompletion: true));
      return;
    }
    unawaited(_endOfTrack());
  }

  Future<void> _endOfTrack() async {
    await _safe(_backend.pause);
    _emitPosition(_state.durationMs);
    _events.add(EngineEvent.trackEnded);
  }

  Future<void> _seek(int ms) async {
    _emitPosition(ms);
    await _safe(() => _backend.seek(Duration(milliseconds: ms)));
  }

  void _emitPosition(int ms) {
    _posMs = ms;
    if (!_positions.isClosed) _positions.add(ms);
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // The player may be mid-load or disposed; the next event re-syncs us.
    }
  }

  void _setState(EngineState next) {
    if (_disposed) return;
    final merged = next.copyWith(
      playing: _backendPlaying || _inGap,
      inGap: _inGap && !_holding,
      holding: _holding,
      hasNext: _onNext != null,
      hasPrevious: _onPrevious != null,
    );
    if (merged == _state) return;
    _state = merged;
    if (!_states.isClosed) _states.add(merged);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _gapTimer?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _states.close();
    await _positions.close();
    await _events.close();
    await _backend.dispose();
  }
}

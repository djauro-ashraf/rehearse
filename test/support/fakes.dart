import 'dart:async';

import 'package:rehearse/engine/audio_backend.dart';
import 'package:rehearse/engine/drill_engine.dart';

/// A player that only exists in memory. Time moves when the test says so.
class FakeBackend implements AudioBackend {
  FakeBackend({this.durationMs = 60000});

  final int durationMs;
  int _pos = 0;
  bool _playing = false;
  bool _completedFired = false;

  double speed = 1.0;
  double pitch = 0.0;
  String? loadedPath;
  int seekCount = 0;

  final _positions = StreamController<Duration>.broadcast();
  final _playingStream = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _interruptions = StreamController<void>.broadcast();

  /// Simulates unplugging headphones / an incoming call.
  void interrupt() => _interruptions.add(null);

  @override
  Stream<void> get interruptions => _interruptions.stream;

  bool get isPlaying => _playing;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<bool> get playingStream => _playingStream.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Duration get position => Duration(milliseconds: _pos);

  @override
  Future<Duration?> load(String path) async {
    loadedPath = path;
    _pos = 0;
    _completedFired = false;
    return Duration(milliseconds: durationMs);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _playingStream.add(true);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playingStream.add(false);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _playingStream.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCount++;
    _pos = position.inMilliseconds;
    _completedFired = false;
    _positions.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  @override
  Future<void> setPitchSemitones(double semitones) async => pitch = semitones;

  /// Advances real time by [ms]: audio moves at `speed` × real time.
  void tick(int ms) {
    if (!_playing || _completedFired) return;
    _pos += (ms * speed).round();
    if (_pos >= durationMs) {
      _pos = durationMs;
      _completedFired = true;
      _positions.add(Duration(milliseconds: _pos));
      _completed.add(null);
      return;
    }
    _positions.add(Duration(milliseconds: _pos));
  }

  @override
  Future<void> dispose() async {}
}

class _FakeTimer implements Timer {
  _FakeTimer(this.remainingMs, this.callback);

  int remainingMs;
  final void Function() callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

/// Drives a [FakeBackend] and fake timers forward together.
class SimClock {
  SimClock(this.backend);

  final FakeBackend backend;
  final List<_FakeTimer> _timers = [];

  TimerFactory get timers => (duration, callback) {
        final timer = _FakeTimer(duration.inMilliseconds, callback);
        _timers.add(timer);
        return timer;
      };

  /// Runs [ms] of simulated real time in 20 ms steps, letting async work
  /// (seeks, stream events) settle between steps.
  Future<void> run(int ms) async {
    var left = ms;
    while (left > 0) {
      const step = 20;
      backend.tick(step);
      for (final timer in List<_FakeTimer>.of(_timers)) {
        if (!timer._active) continue;
        timer.remainingMs -= step;
        if (timer.remainingMs <= 0) {
          timer._active = false;
          timer.callback();
        }
      }
      await settle();
      left -= step;
    }
  }

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../engine/audio_backend.dart';

/// [AudioBackend] on top of `just_audio` (ExoPlayer on Android, AVPlayer on
/// iOS). Speed uses time-stretching, so changing it never changes the pitch.
class JustAudioBackend implements AudioBackend {
  JustAudioBackend() {
    // ~30 position updates a second keeps A–B loop points accurate to a few
    // milliseconds without needing any native code.
    _positions = _player.createPositionStream(
      minPeriod: const Duration(milliseconds: 16),
      maxPeriod: const Duration(milliseconds: 33),
    );
    unawaited(_listenToSession());
  }

  final AudioPlayer _player = AudioPlayer();
  late final Stream<Duration> _positions;
  final StreamController<void> _interruptions = StreamController<void>.broadcast();
  final List<StreamSubscription<Object?>> _sessionSubscriptions = [];

  Future<void> _listenToSession() async {
    final session = await AudioSession.instance;
    _sessionSubscriptions
      ..add(session.becomingNoisyEventStream.listen((_) => _interruptions.add(null)))
      ..add(session.interruptionEventStream.listen((event) {
        // Ducking just lowers the volume; anything else means "stop".
        if (event.begin && event.type != AudioInterruptionType.duck) {
          _interruptions.add(null);
        }
      }));
  }

  @override
  Stream<void> get interruptions => _interruptions.stream;

  @override
  Stream<Duration> get positionStream => _positions;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((state) => state == ProcessingState.completed);

  @override
  Duration get position => _player.position;

  @override
  Future<Duration?> load(String path) => _player.setFilePath(path);

  // `play()` only completes when playback stops, so it must never be awaited.
  @override
  Future<void> play() async => unawaited(_player.play());

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setPitchSemitones(double semitones) =>
      _player.setPitch(math.pow(2, semitones / 12).toDouble());

  @override
  Future<void> dispose() async {
    for (final sub in _sessionSubscriptions) {
      await sub.cancel();
    }
    await _interruptions.close();
    await _player.dispose();
  }

  /// Reads a file's duration with a throw-away player. Null if it can't be
  /// decoded.
  static Future<int?> probeDurationMs(String path) async {
    final probe = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    try {
      final duration = await probe.setFilePath(path);
      return duration?.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await probe.dispose();
    }
  }
}

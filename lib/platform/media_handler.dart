import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../engine/drill_engine.dart';
import '../engine/engine_state.dart';
import '../engine/idle_release.dart';

/// Connects the engine to the system: notification, lock screen, headset and
/// Bluetooth buttons, and background playback.
///
/// Background behaviour (carried over from the original app, where it fixed
/// "the app gets killed when I open another app"):
///
/// * While practising the service stays in the foreground even when playback
///   is **paused** (`androidStopForegroundOnPause: false` in `main.dart`), so
///   switching apps mid-edit doesn't get the app reclaimed.
/// * After 15 minutes paused with no activity it lets go ([IdleRelease]).
/// * Swiping the app away keeps audio playing, but if nothing is playing at
///   that moment the service stops.
/// * "Your turn" gaps and pauses between routine steps count as *playing*, so
///   the system keeps the CPU awake through them.
/// * The notification offers play/pause only while practising (so a stray tap
///   can't change what you're editing) and adds previous/next step only while
///   a routine runs.
class RehearseAudioHandler extends BaseAudioHandler with SeekHandler {
  RehearseAudioHandler(
    this._engine, {
    Duration idleRelease = const Duration(minutes: 15),
  }) {
    _idle = IdleRelease(duration: idleRelease, onRelease: () => unawaited(stop()));
    _states = _engine.states.listen(_sync);
    // Seeks and edits while paused count as activity.
    _positions = _engine.positions.listen((_) {
      if (!_engine.state.playing) {
        _idle.touch(hasTrack: _engine.state.hasTrack);
      }
    });
    _sync(_engine.state);
  }

  final DrillEngine _engine;
  late final IdleRelease _idle;
  late final StreamSubscription<EngineState> _states;
  late final StreamSubscription<int> _positions;
  String? _shownTrackId;
  String? _shownLabel;
  int _shownDurationMs = -1;
  bool _announcedIdle = false;

  void _sync(EngineState s) {
    _idle.update(playing: s.playing, hasTrack: s.hasTrack);

    final label = (s.hasNext || s.hasPrevious) ? 'Routine' : 'Practice';
    if (s.trackId != _shownTrackId ||
        s.durationMs != _shownDurationMs ||
        label != _shownLabel) {
      _shownTrackId = s.trackId;
      _shownDurationMs = s.durationMs;
      _shownLabel = label;
      mediaItem.add(
        s.hasTrack
            ? MediaItem(
                id: s.trackId!,
                title: s.title,
                album: 'Rehearse',
                artist: label,
                duration: s.durationMs > 0
                    ? Duration(milliseconds: s.durationMs)
                    : null,
              )
            : null,
      );
    }

    // After an idle release or a dismissed notification, stay quiet until
    // audio actually starts again (otherwise any edit would bring it back).
    if (_idle.released && !s.playing) {
      if (!_announcedIdle) {
        _announcedIdle = true;
        playbackState.add(PlaybackState(
          processingState: AudioProcessingState.idle,
          playing: false,
        ));
      }
      return;
    }
    _announcedIdle = false;

    final controls = <MediaControl>[
      if (s.hasPrevious) MediaControl.skipToPrevious,
      if (s.playing) MediaControl.pause else MediaControl.play,
      if (s.hasNext) MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: [for (var i = 0; i < controls.length; i++) i],
        processingState: !s.hasTrack
            ? AudioProcessingState.idle
            : s.loading
                ? AudioProcessingState.loading
                : AudioProcessingState.ready,
        playing: s.playing,
        updatePosition: Duration(milliseconds: _engine.positionMs),
        bufferedPosition: Duration(milliseconds: s.durationMs),
        speed: s.speed,
      ),
    );
  }

  @override
  Future<void> play() => _engine.play();

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> seek(Duration position) =>
      _engine.seekTo(position.inMilliseconds);

  @override
  Future<void> skipToNext() => _engine.skipNext();

  @override
  Future<void> skipToPrevious() => _engine.skipPrevious();

  /// Also called when the notification is dismissed.
  @override
  Future<void> stop() async {
    _idle.markReleased();
    await _engine.pause();
    await super.stop();
  }

  /// The app was swiped away: audio that is playing keeps going; otherwise
  /// there is nothing to keep alive.
  @override
  Future<void> onTaskRemoved() async {
    if (!_engine.state.playing) await stop();
  }

  Future<void> dispose() async {
    _idle.dispose();
    await _states.cancel();
    await _positions.cancel();
  }
}

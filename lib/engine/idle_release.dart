import 'dart:async';

import 'drill_engine.dart' show TimerFactory;

/// Decides when the app should let go of its foreground service.
///
/// While you are practising, Android keeps the app alive only if it stays a
/// foreground service, even when playback is *paused*: otherwise opening
/// another app for a minute can get it killed. So we stay foreground while
/// paused, but not forever: after [duration] with no activity we release it
/// (the notification goes away) and stay released until audio starts again.
class IdleRelease {
  IdleRelease({
    required this.onRelease,
    this.duration = const Duration(minutes: 15),
    TimerFactory? timers,
  }) : _timers = timers ?? Timer.new;

  final Duration duration;
  final void Function() onRelease;
  final TimerFactory _timers;

  Timer? _timer;
  bool _released = false;

  /// True after the release fired (or [markReleased] was called) and until
  /// audio plays again.
  bool get released => _released;

  /// Call on every playback-state change.
  void update({required bool playing, required bool hasTrack}) {
    if (playing) {
      _released = false;
      _cancel();
      return;
    }
    _arm(hasTrack);
  }

  /// Call when the user does something while paused (a seek, an edit): the
  /// idle countdown starts over.
  void touch({required bool hasTrack}) => _arm(hasTrack);

  /// The service was stopped on purpose (notification dismissed, swipe-away).
  void markReleased() {
    _cancel();
    _released = true;
  }

  void _arm(bool hasTrack) {
    _cancel();
    if (_released || !hasTrack) return;
    _timer = _timers(duration, () {
      _timer = null;
      _released = true;
      onRelease();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => _cancel();
}

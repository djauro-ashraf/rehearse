/// The smallest surface the drill engine needs from an audio player.
///
/// Keeping this boundary tiny means the loop logic can be unit-tested with a
/// fake player, and the real player (`just_audio`) can be swapped without
/// touching any practice code.
abstract interface class AudioBackend {
  /// Emits the playback position often (≥ 25 Hz) while playing, and once after
  /// every seek.
  Stream<Duration> get positionStream;

  /// True while the player is (or wants to be) playing.
  Stream<bool> get playingStream;

  /// Fires when playback reaches the end of the file.
  Stream<void> get completedStream;

  /// Fires when the system asks us to stop: headphones were unplugged, or a
  /// call / another app interrupted playback. (A player that is actually
  /// playing already pauses itself; this lets the engine also cancel the
  /// silent waits that look like playback to the rest of the app.)
  Stream<void> get interruptions;

  Duration get position;

  /// Opens [path]. Returns the duration if the player knows it.
  Future<Duration?> load(String path);

  /// Starts playback. Must not wait for playback to finish.
  Future<void> play();

  Future<void> pause();

  /// Stops playback and releases the open file.
  Future<void> stop();

  Future<void> seek(Duration position);

  /// Speed multiplier. Pitch must not change with speed.
  Future<void> setSpeed(double speed);

  /// Pitch shift in semitones, independent of speed.
  Future<void> setPitchSemitones(double semitones);

  Future<void> dispose();
}

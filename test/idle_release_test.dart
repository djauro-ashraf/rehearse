import 'package:flutter_test/flutter_test.dart';
import 'package:rehearse/engine/idle_release.dart';

import 'support/fakes.dart';

void main() {
  late SimClock clock;
  late int releases;
  late IdleRelease idle;

  setUp(() {
    clock = SimClock(FakeBackend());
    releases = 0;
    idle = IdleRelease(
      duration: const Duration(minutes: 15),
      timers: clock.timers,
      onRelease: () => releases++,
    );
  });

  tearDown(() => idle.dispose());

  const fifteenMinutes = 15 * 60 * 1000;

  test('releases after 15 minutes paused', () async {
    idle.update(playing: false, hasTrack: true);
    await clock.run(fifteenMinutes - 1000);
    expect(releases, 0);
    await clock.run(2000);
    expect(releases, 1);
    expect(idle.released, isTrue);
  });

  test('never releases while playing', () async {
    idle.update(playing: true, hasTrack: true);
    await clock.run(fifteenMinutes + 5000);
    expect(releases, 0);
  });

  test('playing again cancels a pending release', () async {
    idle.update(playing: false, hasTrack: true);
    await clock.run(10 * 60 * 1000);
    idle.update(playing: true, hasTrack: true);
    await clock.run(10 * 60 * 1000);
    expect(releases, 0);
  });

  test('activity while paused restarts the countdown', () async {
    idle.update(playing: false, hasTrack: true);
    await clock.run(10 * 60 * 1000);
    idle.touch(hasTrack: true);
    await clock.run(10 * 60 * 1000);
    expect(releases, 0, reason: '20 min since pausing, but only 10 since the last touch');
    await clock.run(6 * 60 * 1000);
    expect(releases, 1);
  });

  test('once released it stays released (touches do not revive it) until audio plays', () async {
    idle.update(playing: false, hasTrack: true);
    await clock.run(fifteenMinutes + 1000);
    expect(idle.released, isTrue);
    idle.touch(hasTrack: true);
    idle.update(playing: false, hasTrack: true);
    await clock.run(fifteenMinutes * 2);
    expect(releases, 1, reason: 'no second release');
    idle.update(playing: true, hasTrack: true);
    expect(idle.released, isFalse);
    idle.update(playing: false, hasTrack: true);
    await clock.run(fifteenMinutes + 1000);
    expect(releases, 2);
  });

  test('nothing loaded means nothing to release', () async {
    idle.update(playing: false, hasTrack: false);
    await clock.run(fifteenMinutes + 1000);
    expect(releases, 0);
  });

  test('a deliberate stop (dismissed notification) releases at once and stays quiet', () async {
    idle.markReleased();
    expect(idle.released, isTrue);
    idle.update(playing: false, hasTrack: true);
    await clock.run(fifteenMinutes * 2);
    expect(releases, 0, reason: 'already released; no timer');
  });
}

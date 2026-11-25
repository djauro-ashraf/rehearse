import 'package:flutter_test/flutter_test.dart';
import 'package:rehearse/domain/gap.dart';
import 'package:rehearse/domain/speed_trainer.dart';
import 'package:rehearse/engine/drill_engine.dart';
import 'package:rehearse/engine/engine_state.dart';

import 'support/fakes.dart';

void main() {
  late FakeBackend backend;
  late SimClock clock;
  late DrillEngine engine;

  Future<void> open({
    int? a,
    int? b,
    bool loopOn = false,
    int repeats = 0,
    Gap gap = const Gap.none(),
    double speed = 1.0,
    int startMs = 0,
  }) async {
    await engine.load(
      trackId: 't',
      path: '/audio/t.mp3',
      title: 'Track',
      startMs: startMs,
      loopStartMs: a,
      loopEndMs: b,
      loopOn: loopOn,
      repeats: repeats,
      gap: gap,
      speed: speed,
    );
    await clock.settle();
  }

  setUp(() {
    backend = FakeBackend(durationMs: 60000);
    clock = SimClock(backend);
    engine = DrillEngine(backend, timers: clock.timers);
  });

  group('loading', () {
    test('restores speed, loop and position', () async {
      await open(a: 10000, b: 20000, loopOn: true, speed: 0.75, startMs: 12000);
      expect(engine.state.durationMs, 60000);
      expect(engine.state.speed, 0.75);
      expect(backend.speed, 0.75);
      expect(engine.state.loopOn, isTrue);
      expect(engine.positionMs, 12000);
    });

    test('starts at A when the saved position is outside the loop', () async {
      await open(a: 10000, b: 20000, loopOn: true, startMs: 40000);
      expect(engine.positionMs, 10000);
    });

    test('an invalid saved loop is dropped', () async {
      await open(a: 70000, b: 80000, loopOn: true);
      expect(engine.state.hasLoop, isFalse);
      expect(engine.state.loopOn, isFalse);
    });
  });

  group('looping', () {
    test('wraps from B back to A and counts passes', () async {
      await open(a: 10000, b: 12000, loopOn: true);
      await engine.play();
      await clock.run(7000); // 2 s loop ≈ 3 passes in 7 s
      expect(engine.state.pass, greaterThanOrEqualTo(3));
      expect(engine.positionMs, greaterThanOrEqualTo(10000));
      expect(engine.positionMs, lessThan(12100));
      expect(engine.state.playing, isTrue);
    });

    test('never plays beyond B', () async {
      await open(a: 10000, b: 12000, loopOn: true);
      await engine.play();
      var maxSeen = 0;
      final sub = engine.positions.listen((p) {
        if (p > maxSeen) maxSeen = p;
      });
      await clock.run(10000);
      await sub.cancel();
      expect(maxSeen, lessThanOrEqualTo(12000));
    });

    test('slow speed still wraps once per loop length / speed', () async {
      await open(a: 10000, b: 12000, loopOn: true, speed: 0.5);
      await engine.play();
      await clock.run(9000); // 2 s of audio at 0.5× = 4 s per pass → 2 passes
      expect(engine.state.pass, 2);
    });

    test('plays on past B when the loop is off', () async {
      await open(a: 10000, b: 12000, loopOn: false, startMs: 11000);
      await engine.play();
      await clock.run(3000);
      expect(engine.positionMs, greaterThan(12000));
      expect(engine.state.pass, 0);
    });

    test('seeking while looping stays inside the loop', () async {
      await open(a: 10000, b: 12000, loopOn: true);
      await engine.seekTo(50000);
      expect(engine.positionMs, 11999);
      await engine.seekTo(1000);
      expect(engine.positionMs, 10000);
    });

    test('play from outside the loop jumps to A first', () async {
      await open(a: 10000, b: 12000, loopOn: false, startMs: 30000);
      await engine.setLoopOn(true);
      expect(engine.positionMs, 10000);
    });

    test('moving the region resets the pass counter', () async {
      await open(a: 10000, b: 12000, loopOn: true);
      await engine.play();
      await clock.run(3000);
      expect(engine.state.pass, greaterThan(0));
      engine.setLoopRegion(10000, 13000);
      expect(engine.state.pass, 0);
    });

    test('a region moved ahead of the playhead pulls it back', () async {
      await open(a: 10000, b: 12000, loopOn: true);
      await engine.play();
      await clock.run(500);
      engine.setLoopRegion(20000, 22000);
      await clock.run(100);
      expect(engine.positionMs, greaterThanOrEqualTo(20000));
    });

    test('a loop that ends at the end of the track keeps looping', () async {
      await open(a: 58000, b: 60000, loopOn: true, startMs: 58000);
      await engine.play();
      await clock.run(6000);
      expect(engine.state.pass, greaterThanOrEqualTo(2));
      expect(engine.state.playing, isTrue);
    });
  });

  group('repeat target', () {
    test('stops at A after the requested passes and announces it', () async {
      await open(a: 10000, b: 11000, loopOn: true, repeats: 3);
      final events = <EngineEvent>[];
      final sub = engine.events.listen(events.add);
      await engine.play();
      await clock.run(6000);
      await sub.cancel();
      expect(engine.state.pass, 3);
      expect(engine.state.targetReached, isTrue);
      expect(engine.state.playing, isFalse);
      expect(engine.positionMs, 10000);
      expect(events, [EngineEvent.targetReached]);
    });

    test('pressing play again starts a fresh drill', () async {
      await open(a: 10000, b: 11000, loopOn: true, repeats: 2);
      await engine.play();
      await clock.run(4000);
      expect(engine.state.targetReached, isTrue);
      await engine.play();
      expect(engine.state.pass, 0);
      expect(engine.state.targetReached, isFalse);
      expect(engine.state.playing, isTrue);
    });
  });

  group('gap ("your turn")', () {
    test('pauses for the loop length, then plays again', () async {
      await open(a: 10000, b: 11000, loopOn: true, gap: const Gap.clip());
      await engine.play();
      await clock.run(1200); // first pass done → in gap
      expect(engine.state.pass, 1);
      expect(engine.state.inGap, isTrue);
      expect(engine.state.playing, isTrue, reason: 'the user is still in the drill');
      expect(backend.isPlaying, isFalse);
      expect(engine.positionMs, 10000);
      await clock.run(1200); // gap (1 s) over
      expect(engine.state.inGap, isFalse);
      expect(backend.isPlaying, isTrue);
    });

    test('pausing during a gap cancels it', () async {
      await open(a: 10000, b: 11000, loopOn: true, gap: const Gap.fixed(5000));
      await engine.play();
      await clock.run(1200);
      expect(engine.state.inGap, isTrue);
      await engine.pause();
      expect(engine.state.inGap, isFalse);
      expect(engine.state.playing, isFalse);
      await clock.run(6000);
      expect(backend.isPlaying, isFalse);
    });

    test('play during a gap skips the wait', () async {
      await open(a: 10000, b: 11000, loopOn: true, gap: const Gap.fixed(5000));
      await engine.play();
      await clock.run(1200);
      await engine.play();
      expect(engine.state.inGap, isFalse);
      expect(backend.isPlaying, isTrue);
    });
  });

  group('speed trainer', () {
    test('speeds up every N passes until the target', () async {
      await open(a: 10000, b: 11000, loopOn: true);
      await engine.setTrainer(const SpeedTrainer(
        enabled: true,
        start: 0.5,
        target: 0.6,
        step: 0.05,
        everyPasses: 2,
      ));
      expect(engine.state.speed, 0.5);
      await engine.play();
      await clock.run(60000);
      expect(engine.state.speed, 0.6);
      expect(backend.speed, 0.6);
    });
  });

  group('applyLoop', () {
    test('sets the whole drill at once', () async {
      await open();
      await engine.applyLoop(
        startMs: 20000,
        endMs: 25000,
        speed: 0.8,
        pitch: 2,
        repeats: 4,
        gap: const Gap.fixed(1000),
      );
      final s = engine.state;
      expect((s.loopStartMs, s.loopEndMs, s.loopOn), (20000, 25000, true));
      expect((s.speed, s.pitch, s.repeats), (0.8, 2.0, 4));
      expect(backend.pitch, 2.0);
      expect(engine.positionMs, 20000);
    });
  });

  group('end of track', () {
    test('without a loop the engine pauses and reports it', () async {
      await open(startMs: 59000);
      final events = <EngineEvent>[];
      final sub = engine.events.listen(events.add);
      await engine.play();
      await clock.run(1500);
      await sub.cancel();
      expect(events, [EngineEvent.trackEnded]);
      expect(engine.state.playing, isFalse);
    });

    test('play at the end restarts from the beginning', () async {
      await open(startMs: 59950);
      await engine.play();
      expect(engine.positionMs, 0);
    });
  });

  group('play one range', () {
    test('plays once, pauses at the end, and leaves the loop alone', () async {
      await open(a: 10000, b: 12000, loopOn: true);
      await engine.playRange(30000, 31000);
      await clock.settle();
      expect(engine.state.playing, isTrue);
      await clock.run(1500);
      expect(engine.positionMs, 31000);
      expect(engine.state.playing, isFalse);
      expect((engine.state.loopStartMs, engine.state.loopEndMs, engine.state.loopOn),
          (10000, 12000, true));
      expect(engine.state.pass, 0);
    });

    test('a seek takes control back', () async {
      await open();
      await engine.playRange(30000, 40000);
      await clock.run(200);
      await engine.seekTo(50000);
      await clock.run(5000);
      expect(engine.positionMs, greaterThan(50000));
      expect(engine.state.playing, isTrue, reason: 'no stray stop at the old range end');
    });
  });

  group('hold (pause between routine steps)', () {
    test('counts as playing, then announces it is over', () async {
      await open();
      final events = <EngineEvent>[];
      final sub = engine.events.listen(events.add);
      engine.hold(1000);
      expect(engine.state.holding, isTrue);
      expect(engine.state.inGap, isFalse, reason: 'distinct from a gap between passes');
      expect(engine.state.playing, isTrue, reason: 'keeps the wake lock / notification alive');
      await clock.run(1100);
      await sub.cancel();
      expect(events, [EngineEvent.holdEnded]);
      expect(engine.state.holding, isFalse);
    });

    test('pressing play skips the wait', () async {
      await open();
      final events = <EngineEvent>[];
      final sub = engine.events.listen(events.add);
      engine.hold(5000);
      await engine.play();
      await clock.settle();
      await sub.cancel();
      expect(events, [EngineEvent.holdEnded]);
    });

    test('pausing cancels it without announcing anything', () async {
      await open();
      final events = <EngineEvent>[];
      final sub = engine.events.listen(events.add);
      engine.hold(1000);
      await engine.pause();
      await clock.run(1500);
      await sub.cancel();
      expect(events, isEmpty);
      expect(engine.state.playing, isFalse);
    });
  });

  group('unlimited repeats', () {
    test('a loop with 0 repeats never stops by itself', () async {
      await open(a: 10000, b: 11000, loopOn: true, repeats: 0);
      await engine.play();
      await clock.run(15000);
      expect(engine.state.targetReached, isFalse);
      expect(engine.state.playing, isTrue);
      expect(engine.state.pass, greaterThan(10));
    });
  });

  group('interruptions (headphones out, incoming call)', () {
    test('a silent gap is cancelled, so audio does not resume from the speaker', () async {
      await open(a: 10000, b: 11000, loopOn: true, gap: const Gap.fixed(5000));
      await engine.play();
      await clock.run(1200);
      expect(engine.state.inGap, isTrue);
      backend.interrupt();
      await clock.settle();
      expect(engine.state.inGap, isFalse);
      expect(engine.state.playing, isFalse);
      await clock.run(6000);
      expect(backend.isPlaying, isFalse, reason: 'the gap timer must not restart playback');
    });

    test('a pause between routine steps is cancelled too', () async {
      await open();
      engine.hold(5000);
      backend.interrupt();
      await clock.settle();
      expect(engine.state.holding, isFalse);
    });

    test('ordinary playback is left to the player', () async {
      await open();
      await engine.play();
      await clock.run(200);
      backend.interrupt();
      await clock.settle();
      expect(backend.isPlaying, isTrue, reason: 'the real player pauses itself');
    });
  });
}

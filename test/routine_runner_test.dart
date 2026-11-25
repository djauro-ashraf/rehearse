import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rehearse/domain/gap.dart';
import 'package:rehearse/domain/loop.dart';
import 'package:rehearse/domain/routine.dart';
import 'package:rehearse/domain/track.dart';
import 'package:rehearse/engine/drill_engine.dart';
import 'package:rehearse/engine/routine_runner.dart';

import 'support/fakes.dart';

void main() {
  late FakeBackend backend;
  late SimClock clock;
  late DrillEngine engine;
  late RoutineRunner runner;

  const loopA = Loop(id: 'a', name: 'A', startMs: 1000, endMs: 2000, createdAtMs: 0);
  const loopB = Loop(id: 'b', name: 'B', startMs: 5000, endMs: 6000, createdAtMs: 0, speed: 0.5);
  const track = Track(
    id: 't',
    title: 'T',
    fileName: 't.mp3',
    durationMs: 60000,
    sizeBytes: 1,
    addedAtMs: 0,
    loops: [loopA, loopB],
  );

  setUp(() {
    backend = FakeBackend(durationMs: 60000);
    clock = SimClock(backend);
    engine = DrillEngine(backend, timers: clock.timers);
    runner = RoutineRunner(engine: engine, pathFor: (t) => '/audio/${t.fileName}');
  });

  List<ResolvedStep> steps({int repeatsA = 2, int repeatsB = 2}) => [
        ResolvedStep(step: RoutineStep(id: '1', trackId: 't', loopId: 'a', repeats: repeatsA), track: track, loop: loopA),
        ResolvedStep(step: RoutineStep(id: '2', trackId: 't', loopId: 'b', repeats: repeatsB), track: track, loop: loopB),
      ];

  test('plays each step its number of times, then finishes', () async {
    await runner.start(steps());
    await clock.settle();
    expect(runner.state.index, 0);
    expect(backend.loadedPath, '/audio/t.mp3');
    await clock.run(2600); // step A: 2 passes of 1 s
    expect(runner.state.index, 1);
    expect(engine.state.loopStartMs, 5000);
    expect(backend.speed, 0.5);
    await clock.run(5200); // step B at 0.5×: 2 passes of 2 s
    expect(runner.state.status, RunnerStatus.finished);
    expect(engine.state.playing, isFalse);
  });

  test('rounds repeat the whole routine', () async {
    await runner.start(steps(repeatsA: 1, repeatsB: 1), rounds: 2);
    await clock.run(1300);
    expect(runner.state.index, 1);
    await clock.run(2600);
    expect(runner.state.round, 2);
    expect(runner.state.index, 0);
    expect(runner.state.isActive, isTrue);
  });

  test('next and previous jump between steps', () async {
    await runner.start(steps());
    await clock.settle();
    await runner.next();
    expect(runner.state.index, 1);
    await runner.previous();
    expect(runner.state.index, 0);
    expect(engine.state.hasNext, isTrue);
    expect(engine.state.hasPrevious, isTrue);
  });

  test('stop pauses and clears the skip buttons', () async {
    await runner.start(steps());
    await clock.settle();
    await runner.stop();
    expect(runner.state.status, RunnerStatus.idle);
    expect(engine.state.playing, isFalse);
    expect(engine.state.hasNext, isFalse);
  });

  test('a gap is honoured between passes', () async {
    const gapped = Loop(id: 'g', name: 'G', startMs: 1000, endMs: 2000, createdAtMs: 0, gap: Gap.clip());
    final step = ResolvedStep(
      step: const RoutineStep(id: 'x', trackId: 't', loopId: 'g', repeats: 2),
      track: track,
      loop: gapped,
    );
    await runner.start([step]);
    await clock.run(1200);
    expect(engine.state.inGap, isTrue);
  });

  test('resolveRoutine drops steps whose loop or track is gone', () {
    const routine = Routine(
      id: 'r',
      name: 'R',
      createdAtMs: 0,
      updatedAtMs: 0,
      steps: [
        RoutineStep(id: '1', trackId: 't', loopId: 'a'),
        RoutineStep(id: '2', trackId: 't', loopId: 'gone'),
        RoutineStep(id: '3', trackId: 'ghost'),
        RoutineStep(id: '4', trackId: 't'),
      ],
    );
    final resolved = resolveRoutine(routine, const [track]);
    expect(resolved.steps.map((s) => s.step.id).toList(), ['1', '4']);
    expect(resolved.missing, 2);
    expect(resolved.steps.last.label, 'Whole track');
    expect(resolved.steps.last.endMs, 60000);
  });

  test('stepsForAllLoops orders loops by position', () {
    final all = RoutineRunner.stepsForAllLoops(track, repeats: 4);
    expect(all.map((s) => s.loop?.id).toList(), ['a', 'b']);
    expect(all.first.step.repeats, 4);
  });

  group('step pauses and next actions', () {
    RoutineStep step(String id, String loop, {int repeats = 1, int pause = 0, StepNext next = const StepNext.next()}) =>
        RoutineStep(id: id, trackId: 't', loopId: loop, repeats: repeats, pauseAfterMs: pause, next: next);

    ResolvedStep resolved(RoutineStep s) =>
        ResolvedStep(step: s, track: track, loop: s.loopId == 'a' ? loopA : loopB);

    test('a pause after a step is a hold, then the next step starts', () async {
      await runner.start([resolved(step('1', 'a', pause: 2000)), resolved(step('2', 'b'))]);
      await clock.run(1300);
      expect(engine.state.holding, isTrue);
      expect(engine.state.playing, isTrue);
      expect(runner.state.index, 0);
      await clock.run(2100);
      expect(runner.state.index, 1);
    });

    test('"stop here" ends the routine', () async {
      await runner.start([resolved(step('1', 'a', next: const StepNext.stop())), resolved(step('2', 'b'))]);
      await clock.run(1300);
      expect(runner.state.status, RunnerStatus.finished);
      expect(engine.state.playing, isFalse);
    });

    test('"go to step" jumps there (and can loop a subset)', () async {
      await runner.start([
        resolved(step('1', 'a', next: const StepNext.goTo('3'))),
        resolved(step('2', 'b')),
        resolved(step('3', 'b', next: const StepNext.goTo('3'))),
      ]);
      await clock.run(1300);
      expect(runner.state.index, 2, reason: 'skipped step 2');
      await clock.run(2400); // step 3 at 0.5× ≈ 2 s, then goes to itself
      expect(runner.state.index, 2);
      expect(runner.state.isActive, isTrue);
    });

    test('a go-to whose target is gone falls back to the next step', () async {
      await runner.start([
        resolved(step('1', 'a', next: const StepNext.goTo('missing'))),
        resolved(step('2', 'b')),
      ]);
      await clock.run(1300);
      expect(runner.state.index, 1);
    });

    test('"random step" picks a different one', () async {
      final shuffler = RoutineRunner(
        engine: engine,
        pathFor: (t) => '/audio/${t.fileName}',
        random: math.Random(3),
      );
      await shuffler.start([
        resolved(step('1', 'a', next: const StepNext.shuffle())),
        resolved(step('2', 'b')),
        resolved(step('3', 'b')),
      ]);
      await clock.run(1300);
      expect(shuffler.state.index == 0, isFalse);
      await shuffler.stop();
      await shuffler.dispose();
    });

    test('"random step" with nothing else to pick ends the routine', () async {
      await runner.start([resolved(step('1', 'a', next: const StepNext.shuffle()))]);
      await clock.run(1300);
      expect(runner.state.status, RunnerStatus.finished);
    });

    test('a step with unlimited repeats waits for you to move on', () async {
      await runner.start([resolved(step('1', 'a', repeats: 0)), resolved(step('2', 'b'))]);
      await clock.run(6000);
      expect(runner.state.index, 0);
      expect(engine.state.playing, isTrue);
      await runner.next();
      expect(runner.state.index, 1);
    });

    test('estimated length includes repeats and the pause', () {
      final s = resolved(step('1', 'a', repeats: 3, pause: 2000));
      expect(s.estimatedMs, 3 * 1000 + 2000);
    });
  });
}

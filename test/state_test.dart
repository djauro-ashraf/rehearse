import 'package:flutter_test/flutter_test.dart';
import 'package:rehearse/domain/app_settings.dart';
import 'package:rehearse/domain/gap.dart';
import 'package:rehearse/domain/loop.dart';
import 'package:rehearse/domain/marker.dart';
import 'package:rehearse/domain/routine.dart';
import 'package:rehearse/domain/track.dart';
import 'package:rehearse/engine/routine_runner.dart';
import 'package:rehearse/state/practice_controller.dart';
import 'package:rehearse/state/routine_controller.dart';
import 'package:rehearse/state/routines_notifier.dart';

import 'support/harness.dart';

void main() {
  late Harness h;

  setUp(() {
    h = Harness();
  });

  tearDown(Harness.disposeAll);

  group('library', () {
    test('changes are written to the store', () async {
      h.library.rename('t1', '  Lesson 2  ');
      expect(h.track().title, 'Lesson 2');
      final saved = h.store.documents['library']!;
      expect(((saved['tracks']! as List).first as Map)['title'], 'Lesson 2');
    });

    test('blank rename is ignored', () {
      h.library.rename('t1', '   ');
      expect(h.track().title, 'Lesson');
    });

    test('remove deletes the track', () {
      h.library.remove('t1');
      expect(h.library.byId('t1'), isNull);
    });
  });

  group('routines', () {
    const step = RoutineStep(id: 's1', trackId: 't1', loopId: 'l1');
    const other = RoutineStep(id: 's2', trackId: 't1', loopId: 'l2');
    const whole = RoutineStep(id: 's3', trackId: 't2');
    final routine = Routine(
      id: 'r1',
      name: 'R',
      createdAtMs: 0,
      updatedAtMs: 0,
      steps: const [step, other, whole],
    );

    test('purgeLoop removes only that loop\'s steps', () {
      final h2 = Harness(routines: [routine]);
      h2.routines.purgeLoop('t1', 'l1');
      expect(h2.routines.byId('r1')!.steps.map((s) => s.id).toList(), ['s2', 's3']);
      expect(h2.routines.usageOfLoop('t1', 'l2'), 1);
    });

    test('purgeTrack removes every step of the track', () {
      final h2 = Harness(routines: [routine]);
      h2.routines.purgeTrack('t1');
      expect(h2.routines.byId('r1')!.steps.map((s) => s.id).toList(), ['s3']);
    });

    test('duplicate copies steps with fresh ids', () {
      final h2 = Harness(routines: [routine]);
      final copy = h2.routines.duplicate('r1');
      expect(copy.name, 'R copy');
      expect(copy.steps.length, 3);
      expect(copy.steps.first.id == 's1', isFalse);
      expect(h2.container.read(routinesProvider).length, 2);
    });
  });

  group('opening a track', () {
    test('restores the remembered practice setup', () async {
      h = Harness(tracks: [
        sampleTrack(
          lastPlayedAtMs: 5,
          memory: const PracticeMemory(
            positionMs: 5000,
            speed: 0.75,
            pitch: 2,
            loopStartMs: 10000,
            loopEndMs: 20000,
            loopOn: true,
            repeats: 3,
            gap: Gap.clip(),
          ),
        ),
      ]);
      await h.open();
      final s = h.engine.state;
      expect((s.speed, s.pitch, s.repeats), (0.75, 2.0, 3));
      expect((s.loopStartMs, s.loopEndMs, s.loopOn), (10000, 20000, true));
      expect(s.gap, const Gap.clip());
      expect(h.engine.positionMs, 10000, reason: 'resumes inside the loop');
      expect(h.practiceState.trackId, 't1');
      expect(h.track().hasBeenPlayed, isTrue);
    });

    test('opening the already-loaded track keeps it playing', () async {
      await h.open();
      await h.engine.play();
      await h.open();
      expect(h.engine.state.playing, isTrue);
    });
  });

  group('setting A and B', () {
    setUp(() async => h.open());

    test('A at the playhead starts a 10 s loop', () async {
      await h.seek(30000);
      h.practice.setA();
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (30000, 40000));
      expect(h.engine.state.loopOn, isTrue);
    });

    test('B after A closes the loop and previews the end', () async {
      await h.seek(30000);
      h.practice.setA();
      await h.seek(36000);
      h.practice.setB();
      await h.clock.settle();
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (30000, 36000));
      expect(h.engine.positionMs, 31000, reason: 'previews the last 5 s');
      expect(h.engine.state.playing, isTrue);
    });

    test('B without A looks back 10 s', () async {
      await h.seek(15000);
      h.practice.setB();
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (5000, 15000));
    });

    test('no preview when the setting is off', () async {
      h.settings.update((s) => s.copyWith(previewEnabled: false));
      await h.seek(30000);
      h.practice.setA();
      await h.seek(36000);
      h.practice.setB();
      await h.clock.settle();
      expect(h.engine.positionMs, 36000, reason: 'stays at B');
      expect(h.engine.state.playing, isFalse);
    });

    test('lock freezes every edit', () async {
      await h.seek(30000);
      h.practice.setA();
      h.practice.toggleLock();
      h.practice.nudgeA(500);
      h.practice.setB();
      h.practice.dragRegion(1000, 2000);
      h.practice.clearLoop();
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (30000, 40000));
    });

    test('nudging moves one end and respects the minimum length', () async {
      await h.seek(30000);
      h.practice.setA();
      h.practice.nudgeA(500);
      h.practice.nudgeB(-1000);
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (30500, 39000));
      h.practice.nudgeA(99999);
      expect(h.engine.state.loopStartMs, 39000 - 100);
    });

    test('exact time entry', () async {
      h.practice.setAExact(12500);
      h.practice.setBExact(20000);
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (12500, 20000));
    });

    test('toggling the loop with no A–B loops the next 10 s', () async {
      await h.seek(50000);
      await h.practice.toggleLoop();
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (50000, 60000));
      expect(h.engine.state.loopOn, isTrue);
      await h.practice.toggleLoop();
      expect(h.engine.state.loopOn, isFalse);
      expect(h.engine.state.hasLoop, isTrue, reason: 'A–B is kept when switched off');
    });
  });

  group('saved loops', () {
    setUp(() async {
      await h.open();
      h.practice.setAExact(10000);
      h.practice.setBExact(18000);
      await h.practice.setSpeed(0.8);
      await h.practice.setPitch(-1);
      h.practice.setRepeats(5);
      h.practice.setGap(const Gap.clip());
      await h.clock.settle();
    });

    test('saveLoop captures the whole drill', () {
      final loop = h.practice.saveLoop()!;
      expect(loop.name, 'Loop 1');
      expect((loop.startMs, loop.endMs, loop.speed, loop.pitch, loop.repeats, loop.gap),
          (10000, 18000, 0.8, -1.0, 5, const Gap.clip()));
      expect(h.track().loops.length, 1);
      expect(h.practiceState.activeLoopId, loop.id);
      expect(loopIsModified(loop, h.engine.state), isFalse);
    });

    test('editing afterwards marks the loop as modified, update fixes it', () async {
      final loop = h.practice.saveLoop()!;
      await h.practice.setSpeed(0.9);
      expect(loopIsModified(h.track().loopById(loop.id)!, h.engine.state), isTrue);
      h.practice.updateActiveLoop();
      expect(h.track().loopById(loop.id)!.speed, 0.9);
      expect(loopIsModified(h.track().loopById(loop.id)!, h.engine.state), isFalse);
    });

    test('applyLoop sets up the drill and plays', () async {
      final loop = h.practice.saveLoop()!;
      h.practice.setAExact(50000);
      h.practice.setBExact(52000);
      await h.practice.setSpeed(1.5);
      await h.practice.applyLoop(loop);
      await h.clock.settle();
      final s = h.engine.state;
      expect((s.loopStartMs, s.loopEndMs, s.speed), (10000, 18000, 0.8));
      expect(s.playing, isTrue);
      expect(h.engine.positionMs, 10000);
    });

    test('deleting a loop also removes it from routines', () {
      final loop = h.practice.saveLoop()!;
      h.routines.upsert(Routine(
        id: 'r',
        name: 'R',
        createdAtMs: 0,
        updatedAtMs: 0,
        steps: [RoutineStep(id: 's', trackId: 't1', loopId: loop.id)],
      ));
      expect(h.practice.routinesUsing(loop.id), 1);
      h.practice.deleteLoop(loop.id);
      expect(h.track().loops, isEmpty);
      expect(h.routines.byId('r')!.steps, isEmpty);
      expect(h.practiceState.activeLoopId, isNull);
    });

    test('a deleted loop can be restored', () {
      final loop = h.practice.saveLoop()!;
      h.practice.deleteLoop(loop.id);
      h.practice.restoreLoop(loop);
      expect(h.track().loops.single.id, loop.id);
    });

    test('rename', () {
      final loop = h.practice.saveLoop()!;
      h.practice.renameLoop(loop.id, '  Chorus ');
      expect(h.track().loopById(loop.id)!.name, 'Chorus');
    });
  });

  group('stamping', () {
    setUp(() async => h.open());

    test('marks are numbered as you listen through, in an automatic first set', () async {
      await h.seek(5000);
      var result = h.practice.stamp(MarkerTier.mark);
      expect(result.outcome, MarkerOutcome.done);
      expect((result.marker!.label, result.needsName), ('1', false));
      await h.seek(12000);
      result = h.practice.stamp(MarkerTier.mark);
      expect(result.marker!.label, '2');
      expect(h.track().activeSet!.name, 'Set 1');
      expect(h.track().markers.length, 2);
    });

    test('a stamp inserted before existing ones is left blank and asks for a name', () async {
      await h.seek(20000);
      h.practice.stamp(MarkerTier.mark);
      await h.seek(5000);
      final result = h.practice.stamp(MarkerTier.mark);
      expect((result.marker!.label, result.needsName), ('', true));
      expect(h.track().markers.firstWhere((m) => m.positionMs == 20000).label, '1',
          reason: 'existing labels are never renumbered');
    });

    test('a second stamp within 300 ms is refused (per tier)', () async {
      await h.seek(5000);
      h.practice.stamp(MarkerTier.mark);
      await h.seek(5100);
      expect(h.practice.stamp(MarkerTier.mark).outcome, MarkerOutcome.duplicate);
      expect(h.practice.stamp(MarkerTier.minimark).outcome, MarkerOutcome.done);
    });

    test('a minimark needs a mark before it, then nests and restarts numbering per segment', () async {
      await h.seek(3000);
      expect(h.practice.stamp(MarkerTier.minimark).outcome, MarkerOutcome.needsMark);
      expect(h.track().markers, isEmpty, reason: 'nothing was created');

      await h.seek(5000);
      h.practice.stamp(MarkerTier.mark);
      await h.seek(7000);
      expect(h.practice.stamp(MarkerTier.minimark).marker!.label, '1');
      await h.seek(8000);
      expect(h.practice.stamp(MarkerTier.minimark).marker!.label, '2');
      await h.seek(12000);
      h.practice.stamp(MarkerTier.mark);
      await h.seek(14000);
      expect(h.practice.stamp(MarkerTier.minimark).marker!.label, '1', reason: 'new segment, numbering restarts');
    });
  });

  group('marker locks, edits and sets', () {
    const marks = [
      Marker(id: 'a', label: '1', positionMs: 5000),
      Marker(id: 'm', label: '1', positionMs: 7000, tier: MarkerTier.minimark),
      Marker(id: 'b', label: '2', positionMs: 12000),
    ];

    setUp(() async {
      h = Harness(tracks: [sampleTrack(markers: marks)]);
      await h.open();
    });

    test('rename, skip, nudge by 100 ms, move and delete', () {
      expect(h.practice.renameMarker('a', ' Intro '), MarkerOutcome.done);
      expect(h.practice.toggleSkip('a'), MarkerOutcome.done);
      expect(h.practice.nudgeMarker('a', 100), MarkerOutcome.done);
      expect(h.practice.nudgeMarker('a', -100000), MarkerOutcome.done);
      var a = h.track().markers.firstWhere((m) => m.id == 'a');
      expect((a.label, a.skip, a.positionMs), ('Intro', true, 0), reason: 'clamped at the start');
      h.practice.moveMarker('a', 4000);
      a = h.track().markers.firstWhere((m) => m.id == 'a');
      expect(a.positionMs, 4000);
      expect(h.practice.removeMarker('b'), MarkerOutcome.done);
      expect(h.track().markers.length, 2);
    });

    test('locking a tier blocks only that tier, for every kind of change', () async {
      h.practice.toggleMarkerLock(MarkerTier.mark);
      expect(h.track().activeSet!.lockedMarks, isTrue);
      expect(h.practice.renameMarker('a', 'x'), MarkerOutcome.locked);
      expect(h.practice.toggleSkip('a'), MarkerOutcome.locked);
      expect(h.practice.nudgeMarker('a', 100), MarkerOutcome.locked);
      expect(h.practice.moveMarker('a', 1), MarkerOutcome.locked);
      expect(h.practice.removeMarker('a'), MarkerOutcome.locked);
      await h.seek(20000);
      expect(h.practice.stamp(MarkerTier.mark).outcome, MarkerOutcome.locked);
      expect(h.track().markers.firstWhere((m) => m.id == 'a').label, '1');
      // Minimarks are still editable.
      expect(h.practice.renameMarker('m', 'word'), MarkerOutcome.done);
      h.practice.toggleMarkerLock(MarkerTier.mark);
      expect(h.practice.renameMarker('a', 'ok'), MarkerOutcome.done);
    });

    test('clear keeps whatever is locked', () {
      h.practice.toggleMarkerLock(MarkerTier.minimark);
      h.practice.clearMarkers();
      expect(h.track().markers.map((m) => m.id).toList(), ['m']);
    });

    test('stamping sets: create, switch, rename, delete', () async {
      h.practice.createMarkerSet('Reciter B');
      expect(h.track().markerSets.length, 2);
      expect(h.track().activeSet!.name, 'Reciter B');
      expect(h.track().markers, isEmpty, reason: 'a new set starts empty');

      await h.seek(9000);
      h.practice.stamp(MarkerTier.mark);
      expect(h.track().markerSets.last.markers.length, 1);
      expect(h.track().markerSets.first.markers.length, 3, reason: 'the other set is untouched');

      h.practice.selectMarkerSet('s1');
      expect(h.track().markers.length, 3);
      h.practice.renameMarkerSet('s1', 'Reciter A');
      expect(h.track().markerSets.first.name, 'Reciter A');
      h.practice.deleteMarkerSet('s1');
      expect(h.track().markerSets.length, 1);
      expect(h.track().activeSet!.name, 'Reciter B', reason: 'falls back to the remaining set');
    });

    test('each set locks independently', () {
      h.practice.createMarkerSet('B');
      h.practice.toggleMarkerLock(MarkerTier.mark);
      expect(h.track().activeSet!.lockedMarks, isTrue);
      h.practice.selectMarkerSet('s1');
      expect(h.track().activeSet!.lockedMarks, isFalse);
    });
  });

  group('segments', () {
    const marks = [
      Marker(id: 'a', label: '1', positionMs: 5000),
      Marker(id: 'b', label: '2', positionMs: 12000),
    ];

    setUp(() async {
      h = Harness(tracks: [sampleTrack(markers: marks)]);
      await h.open();
    });

    test('loopSegment loops exactly that segment', () async {
      await h.practice.loopSegment(0);
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (5000, 12000));
      await h.practice.loopSegment(1);
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (12000, 120000));
    });

    test('playing a segment once pauses at its end and leaves the loop settings alone', () async {
      await h.practice.playRangeOnce(5000, 6000);
      await h.clock.run(1500);
      expect(h.engine.positionMs, 6000);
      expect(h.engine.state.playing, isFalse);
      expect(h.engine.state.loopOn, isFalse);
    });

    test('jumpSegment loops the neighbour when a loop is on, else just seeks', () async {
      await h.seek(6000);
      await h.practice.jumpSegment(1);
      expect(h.engine.positionMs, 12000);
      expect(h.engine.state.loopOn, isFalse);
      await h.practice.loopSegment(1);
      await h.practice.jumpSegment(-1);
      expect((h.engine.state.loopStartMs, h.engine.state.loopEndMs), (5000, 12000));
    });

    test('"previous" first restarts a segment you are well into', () async {
      await h.seek(15000);
      await h.practice.jumpSegment(-1);
      expect(h.engine.positionMs, 12000);
      await h.practice.jumpSegment(-1);
      expect(h.engine.positionMs, 5000);
    });

    test('loopsFromMarkers creates one loop per mark segment, once', () async {
      expect(h.practice.loopsFromMarkers(), 2);
      expect(h.track().loops.map((l) => l.name).toList(), ['Segment 1', 'Segment 2']);
      expect(h.practice.loopsFromMarkers(), 0);
    });
  });

  group('first open, preview and track navigation', () {
    test('a track you have never played starts at your default speed and pitch', () async {
      h = Harness(settings: const AppSettings(defaultSpeed: 0.8, defaultPitch: 1));
      await h.open();
      expect((h.engine.state.speed, h.engine.state.pitch), (0.8, 1.0));
    });

    test('a played track keeps its own speed', () async {
      h = Harness(
        tracks: [sampleTrack(lastPlayedAtMs: 5, memory: const PracticeMemory(speed: 0.6))],
        settings: const AppSettings(defaultSpeed: 0.8),
      );
      await h.open();
      expect(h.engine.state.speed, 0.6);
    });

    test('no preview when it would be as long as the loop', () async {
      await h.open();
      h.practice.setAExact(10000);
      h.practice.setBExact(13000); // loop 3 s, preview 5 s
      await h.clock.settle();
      expect(h.engine.positionMs, 10000);
      expect(h.engine.state.playing, isFalse);
    });

    test('previous/next track follow natural A→Z order', () async {
      h = Harness(tracks: [
        sampleTrack(id: 'a', title: 'Lesson 10'),
        sampleTrack(id: 'b', title: 'Lesson 2'),
        sampleTrack(id: 'c', title: 'Lesson 1'),
      ]);
      await h.open('b');
      expect(await h.practice.openAdjacent(1), 'a');
      expect(h.engine.state.trackId, 'a');
      expect(await h.practice.openAdjacent(1), isNull, reason: 'last track');
      expect(await h.practice.openAdjacent(-1), 'b');
      expect(await h.practice.openAdjacent(-1), 'c');
      expect(await h.practice.openAdjacent(-1), isNull, reason: 'first track');
    });

    test('the practice view never installs notification skip buttons', () async {
      await h.open();
      expect(h.engine.state.hasNext, isFalse);
      expect(h.engine.state.hasPrevious, isFalse);
    });
  });

  group('remembering where you left off', () {
    test('persist saves position, speed and loop', () async {
      await h.open();
      h.practice.setAExact(10000);
      h.practice.setBExact(20000);
      await h.practice.setSpeed(0.7);
      await h.seek(15000);
      h.practice.persist();
      final memory = h.track().memory;
      expect((memory.positionMs, memory.speed, memory.loopStartMs, memory.loopEndMs, memory.loopOn),
          (15000, 0.7, 10000, 20000, true));
      expect(h.store.documents['library'], isNotNull);
    });
  });

  group('routine controller', () {
    final loops = [
      const Loop(id: 'l1', name: 'One', startMs: 1000, endMs: 3000, createdAtMs: 0),
      const Loop(id: 'l2', name: 'Two', startMs: 5000, endMs: 7000, createdAtMs: 0, speed: 0.5),
    ];

    test('play-all starts the first loop and takes over the skip buttons', () async {
      h = Harness(tracks: [sampleTrack(loops: loops)]);
      final started = await h.routineController.startAllLoops(h.track());
      await h.clock.settle();
      expect(started, isTrue);
      expect(h.engine.state.loopStartMs, 1000);
      expect(h.engine.state.hasNext, isTrue);
      expect(h.container.read(routineControllerProvider).runner.status, RunnerStatus.running);
    });

    test('a track without loops cannot be played as a routine', () async {
      expect(await h.routineController.startAllLoops(h.track()), isFalse);
    });

    test('a routine whose steps all vanished does not start', () async {
      final routine = Routine(
        id: 'r',
        name: 'R',
        createdAtMs: 0,
        updatedAtMs: 0,
        steps: const [RoutineStep(id: 's', trackId: 'gone')],
      );
      expect(await h.routineController.start(routine), isFalse);
    });

    test('opening a track stops a running routine', () async {
      h = Harness(tracks: [sampleTrack(loops: loops), sampleTrack(id: 't2')]);
      await h.routineController.startAllLoops(h.track());
      await h.clock.settle();
      await h.open('t2');
      expect(h.container.read(routineControllerProvider).runner.isActive, isFalse);
      expect(h.engine.state.trackId, 't2');
    });
  });

  group('settings', () {
    test('are saved when changed', () {
      h.settings.update((s) => s.copyWith(themeMode: AppThemeMode.dark, skipSeconds: 10));
      final saved = h.store.documents['settings']!;
      expect(saved['themeMode'], 'dark');
      expect(saved['skipSeconds'], 10);
    });
  });
}

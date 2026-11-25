import 'package:flutter_test/flutter_test.dart';
import 'package:rehearse/core/format.dart';
import 'package:rehearse/domain/app_settings.dart';
import 'package:rehearse/domain/gap.dart';
import 'package:rehearse/domain/loop.dart';
import 'package:rehearse/domain/loop_rules.dart';
import 'package:rehearse/domain/marker.dart';
import 'package:rehearse/domain/routine.dart';
import 'package:rehearse/domain/segments.dart';
import 'package:rehearse/domain/speed_trainer.dart';
import 'package:rehearse/domain/track.dart';

void main() {
  group('LoopRules', () {
    test('speed is clamped and snapped to 5 % steps', () {
      expect(LoopRules.clampSpeed(0.1), 0.25);
      expect(LoopRules.clampSpeed(9), 3.0);
      expect(LoopRules.clampSpeed(0.77), 0.75);
      expect(LoopRules.clampSpeed(1.0), 1.0);
    });

    test('pitch is whole semitones within ±12', () {
      expect(LoopRules.clampPitch(30), 12);
      expect(LoopRules.clampPitch(-30), -12);
      expect(LoopRules.clampPitch(2.4), 2);
    });

    test('region keeps a minimum length and stays inside the track', () {
      expect(LoopRules.region(1000, 1050, 60000), (1000, 1100));
      expect(LoopRules.region(59950, 70000, 60000), (59900, 60000));
      expect(LoopRules.region(-5, 50, 60000), (0, 100));
      expect(LoopRules.region(0, 50, 50), isNull);
    });

    test('regionFrom defaults to 10 s and shifts back near the end', () {
      expect(LoopRules.regionFrom(5000, 60000), (5000, 15000));
      expect(LoopRules.regionFrom(58000, 60000), (58000, 60000));
    });

    test('preview starts before B, and is skipped when it would cover the loop', () {
      expect(LoopRules.previewStart(10000, 20000, 4000), 16000);
      expect(LoopRules.previewStart(10000, 12000, 4000), isNull);
      expect(LoopRules.previewStart(10000, 14000, 4000), isNull);
    });

    test('limits match the original app', () {
      expect(LoopRules.minLoopMs, 100);
      expect(LoopRules.maxRepeats, 999);
      expect(LoopRules.maxPreviewMs, 15000);
      expect(LoopRules.maxStepPauseMs, 600000);
    });

    test('clampStart / clampEnd keep A < B', () {
      expect(LoopRules.clampStart(9999, 5000), 4900);
      expect(LoopRules.clampEnd(100, 5000, 60000), 5100);
      expect(LoopRules.clampEnd(99999, 5000, 60000), 60000);
    });
  });

  group('Gap', () {
    test('resolves real-time length', () {
      expect(const Gap.none().resolveMs(regionMs: 5000, speed: 1), 0);
      expect(const Gap.fixed(1500).resolveMs(regionMs: 5000, speed: 1), 1500);
      expect(const Gap.clip().resolveMs(regionMs: 5000, speed: 1), 5000);
      expect(const Gap.clip().resolveMs(regionMs: 5000, speed: 0.5), 10000);
    });

    test('round-trips through JSON', () {
      for (final gap in [const Gap.none(), const Gap.fixed(2500), const Gap.clip()]) {
        expect(Gap.fromJson(gap.toJson()), gap);
      }
      expect(Gap.fromJson('garbage'), const Gap.none());
    });
  });

  group('SpeedTrainer', () {
    const trainer = SpeedTrainer(enabled: true, start: 0.6, target: 0.8, step: 0.05, everyPasses: 2);

    test('raises speed every N passes and stops at the target', () {
      var speed = 0.6;
      final seen = <double>[];
      for (var pass = 1; pass <= 10; pass++) {
        speed = trainer.speedAfterPass(pass, speed);
        seen.add(speed);
      }
      expect(seen, [0.6, 0.65, 0.65, 0.7, 0.7, 0.75, 0.75, 0.8, 0.8, 0.8]);
    });

    test('does nothing when disabled', () {
      expect(const SpeedTrainer().speedAfterPass(3, 0.6), 0.6);
    });
  });

  group('format', () {
    test('formatMs', () {
      expect(formatMs(0), '0:00');
      expect(formatMs(65400), '1:05');
      expect(formatMs(65400, tenths: true), '1:05.4');
      expect(formatMs(3723000), '1:02:03');
      expect(formatMs(-5), '0:00');
    });

    test('parseTime', () {
      expect(parseTime('83'), 83000);
      expect(parseTime('1:23.5'), 83500);
      expect(parseTime('1:02:03'), 3723000);
      expect(parseTime('1,5'), 1500);
      expect(parseTime(''), isNull);
      expect(parseTime('abc'), isNull);
      expect(parseTime('1:2:3:4'), isNull);
    });

    test('speed and pitch labels', () {
      expect(formatSpeed(0.75), '0.75×');
      expect(formatSpeed(1.0), '1.0×');
      expect(formatSpeed(1.25), '1.25×');
      expect(formatPitch(0), '0 st');
      expect(formatPitch(3), '+3 st');
      expect(formatPitch(-2), '−2 st');
    });

    test('formatSeconds', () {
      expect(formatSeconds(1500), '1.5 s');
      expect(formatSeconds(2000), '2 s');
      expect(formatSeconds(125000), '2 min 5 s');
    });
  });

  group('segments', () {
    const markers = [
      Marker(id: 'c', label: '3', positionMs: 30000),
      Marker(id: 'a', label: '1', positionMs: 5000),
      Marker(id: 'm', label: '1', positionMs: 7000, tier: MarkerTier.minimark),
      Marker(id: 'n', label: '2', positionMs: 9000, tier: MarkerTier.minimark),
      Marker(id: 'b', label: '2', positionMs: 12000),
      Marker(id: 'early', label: 'x', positionMs: 1000, tier: MarkerTier.minimark),
    ];

    test('marks are sorted; minimarks nest inside the mark they fall in', () {
      final segments = buildSegments(markers, 40000);
      expect(segments.map((s) => s.mark.id).toList(), ['a', 'b', 'c']);
      expect(segments.map((s) => (s.startMs, s.endMs)).toList(),
          [(5000, 12000), (12000, 30000), (30000, 40000)]);
      expect(segments[0].minimarks.map((m) => m.id).toList(), ['m', 'n']);
      expect(segments[1].minimarks, isEmpty);
      expect(segments[0].minimarkEndMs(0), 9000);
      expect(segments[0].minimarkEndMs(1), 12000);
    });

    test('a minimark before every mark belongs to no segment but is kept', () {
      final segments = buildSegments(markers, 40000);
      expect(segments.expand((s) => s.minimarks).any((m) => m.id == 'early'), isFalse);
      expect(enclosingSegment(markers, 1000, 40000), isNull);
      expect(enclosingSegment(markers, 8000, 40000)!.mark.id, 'a');
    });

    test('segmentIndexAt', () {
      final segments = buildSegments(markers, 40000);
      expect(segmentIndexAt(segments, 1000), -1);
      expect(segmentIndexAt(segments, 5000), 0);
      expect(segmentIndexAt(segments, 29999), 1);
      expect(segmentIndexAt(segments, 39000), 2);
    });

    test('stamp labels: numbered when appending, blank when inserted earlier', () {
      expect(stampLabel(const [], 5000), (label: '1', needsName: false));
      final marks = [for (final m in markers) if (m.tier == MarkerTier.mark) m];
      expect(stampLabel(marks, 35000), (label: '4', needsName: false));
      expect(stampLabel(marks, 8000), (label: '', needsName: true));
    });

    test('minimark numbering restarts inside each mark segment', () {
      final inA = stampSiblings(MarkerTier.minimark, markers, 8000, 40000);
      expect(inA.map((m) => m.id).toList(), ['m', 'n']);
      final inB = stampSiblings(MarkerTier.minimark, markers, 13000, 40000);
      expect(inB, isEmpty);
      expect(stampLabel(inB, 13000).label, '1');
      expect(stampSiblings(MarkerTier.mark, markers, 8000, 40000).length, 3);
    });
  });

  group('natural ordering', () {
    test('digits compare as numbers, case is ignored', () {
      final names = ['Lesson 10', 'lesson 2', '002.mp3', '010.mp3', 'Lesson 1'];
      names.sort(naturalCompare);
      expect(names, ['002.mp3', '010.mp3', 'Lesson 1', 'lesson 2', 'Lesson 10']);
    });
  });

  group('JSON round trips', () {
    test('Track with loops, markers and memory', () {
      const track = Track(
        id: 't1',
        title: 'Lesson 1',
        fileName: 't1.mp3',
        durationMs: 120000,
        sizeBytes: 4096,
        addedAtMs: 10,
        lastPlayedAtMs: 20,
        memory: PracticeMemory(
          positionMs: 5000,
          speed: 0.75,
          pitch: -2,
          loopStartMs: 1000,
          loopEndMs: 9000,
          loopOn: true,
          repeats: 5,
          gap: Gap.clip(),
          activeLoopId: 'l1',
        ),
        loops: [
          Loop(id: 'l1', name: 'Hook', startMs: 1000, endMs: 9000, createdAtMs: 1, speed: 0.8, repeats: 4, gap: Gap.fixed(1000)),
        ],
        markerSets: [
          MarkerSet(
            id: 's1',
            name: 'Reciter A',
            createdAtMs: 3,
            lockedMarks: true,
            markers: [
              Marker(id: 'm1', label: '1', positionMs: 500, skip: true),
              Marker(id: 'm2', label: '1', positionMs: 800, tier: MarkerTier.minimark),
            ],
          ),
        ],
        activeMarkerSetId: 's1',
        originalName: '001.mp3',
        contentHash: 'abc123',
      );
      final copy = Track.fromJson(track.toJson());
      expect(copy.toJson(), track.toJson());
      expect(copy.loopById('l1')?.name, 'Hook');
      expect(copy.loopById('nope'), isNull);
      expect(copy.activeSet!.name, 'Reciter A');
      expect(copy.markers.length, 2);
      expect(copy.exportName, '001.mp3');
    });

    test('Routine and settings', () {
      const routine = Routine(
        id: 'r',
        name: 'Warm up',
        createdAtMs: 1,
        updatedAtMs: 2,
        rounds: 2,
        shuffle: true,
        steps: [
          RoutineStep(
            id: 's',
            trackId: 't',
            loopId: 'l',
            repeats: 0,
            pauseAfterMs: 3000,
            next: StepNext.goTo('s2'),
          ),
        ],
      );
      expect(Routine.fromJson(routine.toJson()).toJson(), routine.toJson());

      const settings = AppSettings(
        themeMode: AppThemeMode.dark,
        previewEnabled: false,
        previewMs: 2000,
        skipSeconds: 10,
        defaultSpeed: 0.75,
        defaultPitch: -1,
        trainer: SpeedTrainer(enabled: true, start: 0.5, target: 0.9, step: 0.1, everyPasses: 4),
      );
      expect(AppSettings.fromJson(settings.toJson()).toJson(), settings.toJson());
    });

    test('an old flat marker list becomes a single set', () {
      final track = Track.fromJson({
        'id': 't',
        'markers': [
          {'id': 'a', 'label': '1', 'positionMs': 10},
        ],
      });
      expect(track.markerSets.single.name, 'Set 1');
      expect(track.markers.single.id, 'a');
    });

    test('bad data is repaired, never thrown', () {
      final loop = Loop.fromJson({'id': 'x', 'startMs': 5000, 'endMs': 100, 'speed': 99, 'repeats': 5000});
      expect(loop.endMs > loop.startMs, isTrue);
      expect(loop.speed, 3.0);
      expect(loop.repeats, 999);
      expect(Track.fromJson(const {}).title, 'Untitled');
      expect(AppSettings.fromJson(const {'themeMode': 'purple'}).themeMode, AppThemeMode.system);
      expect(AppSettings.fromJson(const {}).previewMs, 5000);
      expect(StepNext.fromJson({'kind': 'goTo'}), const StepNext.next(),
          reason: 'a go-to without a target falls back to "next"');
      expect(RoutineStep.fromJson(const {'repeats': 99999}).repeats, 999);
    });
  });
}

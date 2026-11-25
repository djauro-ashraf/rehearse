import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rehearse/data/audio_importer.dart';
import 'package:rehearse/data/audio_storage.dart';
import 'package:rehearse/data/backup.dart';
import 'package:rehearse/data/document_store.dart';
import 'package:rehearse/data/marker_export.dart';
import 'package:rehearse/data/practice_sheet.dart';
import 'package:rehearse/domain/gap.dart';
import 'package:rehearse/domain/loop.dart';
import 'package:rehearse/domain/marker.dart';
import 'package:rehearse/domain/routine.dart';
import 'package:rehearse/domain/track.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rehearse_test_');
  });

  Future<void> cleanUp() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  }

  group('FileDocumentStore', () {
    test('writes and reads back, debounced writes keep only the latest', () async {
      final store = FileDocumentStore(temp, debounce: const Duration(milliseconds: 10));
      store.write('library', {'n': 1});
      store.write('library', {'n': 2});
      await store.flush();
      expect(await store.read('library'), {'n': 2});
      expect(await File(p.join(temp.path, 'library.json')).exists(), isTrue);
      expect(await File(p.join(temp.path, 'library.json.tmp')).exists(), isFalse);
      await cleanUp();
    });

    test('a missing document reads as null', () async {
      final store = FileDocumentStore(temp);
      expect(await store.read('nothing'), isNull);
      await cleanUp();
    });

    test('a corrupt document is set aside, not fatal', () async {
      await File(p.join(temp.path, 'library.json')).writeAsString('{ not json');
      final store = FileDocumentStore(temp);
      expect(await store.read('library'), isNull);
      final names = temp.listSync().map((e) => p.basename(e.path)).toList();
      expect(names.any((n) => n.startsWith('library.corrupt-')), isTrue);
      await cleanUp();
    });

    test('flush returns once pending writes are on disk', () async {
      final store = FileDocumentStore(temp, debounce: const Duration(hours: 1));
      store.write('settings', {'a': true});
      await store.flush();
      final text = await File(p.join(temp.path, 'settings.json')).readAsString();
      expect(jsonDecode(text), {'a': true});
      await cleanUp();
    });
  });

  group('AudioImporter', () {
    Future<File> makeFile(String name, [String content = 'audio-bytes']) async {
      final file = File(p.join(temp.path, name));
      await file.writeAsString(content);
      return file;
    }

    test('copies the file in, names the track from the file name', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      final importer = AudioImporter(storage: storage, probe: (_) async => 61000);
      final source = await makeFile('my_lesson__03.mp3');
      final track = await importer.import(ImportSource(name: 'my_lesson__03.mp3', path: source.path));
      expect(track, isNotNull);
      expect(track!.title, 'my lesson 03');
      expect(track.originalName, 'my_lesson__03.mp3', reason: 'kept for exports');
      expect(track.durationMs, 61000);
      expect(track.fileName.endsWith('.mp3'), isTrue);
      expect(await storage.exists(track.fileName), isTrue);
      expect(await source.exists(), isTrue, reason: 'the original is never touched');
      await cleanUp();
    });

    test('temporary sources are deleted after import', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      final importer = AudioImporter(storage: storage, probe: (_) async => 1000);
      final source = await makeFile('cache_copy.m4a');
      await importer.import(ImportSource(name: 'x.m4a', path: source.path, isTemporary: true));
      expect(await source.exists(), isFalse);
      await cleanUp();
    });

    test('imports from a byte stream', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      final importer = AudioImporter(storage: storage, probe: (_) async => 5000);
      final track = await importer.import(ImportSource(
        name: 'voice.ogg',
        openRead: () => Stream.value(utf8.encode('streamed')),
      ));
      expect(track, isNotNull);
      expect(await storage.fileFor(track!.fileName).readAsString(), 'streamed');
      expect(track.sizeBytes, 8);
      await cleanUp();
    });

    test('a file that is not audio is rejected and leaves nothing behind', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      final importer = AudioImporter(storage: storage, probe: (_) async => null);
      final source = await makeFile('notes.txt');
      final track = await importer.import(ImportSource(name: 'notes.txt', path: source.path));
      expect(track, isNull);
      expect(storage.directory.listSync(), isEmpty);
      await cleanUp();
    });

    test('a missing source fails cleanly', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      final importer = AudioImporter(storage: storage, probe: (_) async => 1000);
      final track = await importer.import(ImportSource(name: 'gone.mp3', path: p.join(temp.path, 'gone.mp3')));
      expect(track, isNull);
      await cleanUp();
    });

    test('odd extensions fall back to a safe one', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      final importer = AudioImporter(storage: storage, probe: (_) async => 1000);
      final source = await makeFile('noext');
      final track = await importer.import(ImportSource(name: 'noext', path: source.path));
      expect(track!.fileName.endsWith('.audio'), isTrue);
      await cleanUp();
    });

    test('titleFromFileName', () {
      expect(titleFromFileName('a_b  c.mp3'), 'a b c');
      expect(titleFromFileName('.mp3'), '.mp3');
      expect(titleFromFileName('___.wav'), 'Untitled');
    });

    test('AudioStorage reports its size and deletes files', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      await storage.ensureCreated();
      await storage.fileFor('a.mp3').writeAsString('12345');
      await storage.fileFor('b.mp3').writeAsString('123');
      expect(await storage.totalBytes(), 8);
      await storage.delete('a.mp3');
      expect(await storage.totalBytes(), 3);
      await storage.delete('missing.mp3');
      await cleanUp();
    });
  });

  group('PracticeSheet', () {
    final track = Track(
      id: 't',
      title: 'Surah / Lesson',
      fileName: 't.mp3',
      durationMs: 100000,
      sizeBytes: 1,
      addedAtMs: 0,
      loops: const [
        Loop(id: 'l1', name: 'Hook', startMs: 1000, endMs: 5000, createdAtMs: 0, speed: 0.8, gap: Gap.clip()),
        Loop(id: 'l2', name: 'Beyond', startMs: 120000, endMs: 130000, createdAtMs: 0),
      ],
      markerSets: const [
        MarkerSet(
          id: 's1',
          name: 'Reciter A',
          createdAtMs: 0,
          lockedMarks: true,
          markers: [
            Marker(id: 'm2', label: '2', positionMs: 8000, skip: true),
            Marker(id: 'm1', label: '1', positionMs: 2000),
            Marker(id: 'mm', label: '1', positionMs: 3000, tier: MarkerTier.minimark),
            Marker(id: 'm3', label: '3', positionMs: 150000),
          ],
        ),
        MarkerSet(id: 's2', name: 'Reciter B', createdAtMs: 0, markers: [Marker(id: 'x', label: '1', positionMs: 500)]),
      ],
      activeMarkerSetId: 's1',
    );

    test('round-trips through text, keeping sets, tiers, skips and locks', () {
      final sheet = PracticeSheet.parse(PracticeSheet.fromTrack(track).toJsonText());
      expect(sheet.title, 'Surah / Lesson');
      expect(sheet.loops.length, 2);
      expect(sheet.markerSets.map((s) => s.name).toList(), ['Reciter A', 'Reciter B']);
      final a = sheet.markerSets.first;
      expect(a.lockedMarks, isTrue);
      expect(a.markers.where((m) => m.skip).length, 1);
      expect(a.markers.where((m) => m.tier == MarkerTier.minimark).length, 1);
      expect(sheet.loops.first.gap, const Gap.clip());
    });

    test('an old (version 1) sheet with a flat marker list still loads', () {
      final sheet = PracticeSheet.parse(jsonEncode({
        'format': 'rehearse.sheet',
        'version': 1,
        'audio': {'title': 'Old', 'durationMs': 1000},
        'loops': <Object?>[],
        'markers': [
          {'id': 'a', 'label': '1', 'positionMs': 10},
        ],
      }));
      expect(sheet.markerSets.single.markers.single.label, '1');
    });

    test('rejects other json and non-json', () {
      expect(() => PracticeSheet.parse('hello'), throwsA(isA<FormatException>()));
      expect(() => PracticeSheet.parse('{"format":"something.else"}'), throwsA(isA<FormatException>()));
      expect(() => PracticeSheet.parse('[1,2]'), throwsA(isA<FormatException>()));
    });

    test('rebasing re-identifies items and drops markers past the end', () {
      final rebased = PracticeSheet.fromTrack(track).rebasedFor(100000);
      expect(rebased.loops.map((l) => l.name).toList(), ['Hook', 'Beyond']);
      final a = rebased.sets.first;
      expect(a.markers.map((m) => m.label).toList(), ['2', '1', '1'], reason: 'the one at 150 s is dropped');
      expect(a.id == 's1', isFalse);
      expect(a.markers.first.id == 'm2', isFalse);
      expect(a.markers.first.skip, isTrue);
    });

    test('merging skips duplicates, merges same-named sets, and is repeatable', () {
      const base = Track(
        id: 't',
        title: 'x',
        fileName: 'x',
        durationMs: 100000,
        sizeBytes: 0,
        addedAtMs: 0,
        loops: [Loop(id: 'mine', name: 'Mine', startMs: 1000, endMs: 5000, createdAtMs: 0)],
        markerSets: [
          MarkerSet(id: 'own', name: 'reciter a', createdAtMs: 0, markers: [Marker(id: 'k', label: '1', positionMs: 2000)]),
        ],
      );
      final rebased = PracticeSheet.fromTrack(track).rebasedFor(100000);
      final first = mergeInto(base, loops: rebased.loops, sets: rebased.sets);
      expect(first.loopsAdded, 1, reason: 'Hook duplicates the existing 1–5 s loop; Beyond is new');
      expect(first.track.loops.length, 2);
      expect(first.loopIds[rebased.loops.first.id], 'mine');
      expect(first.track.markerSets.length, 2);
      final merged = first.track.markerSets.first;
      expect(merged.id, 'own');
      expect(merged.markers.length, 3, reason: 'the mark at 2 s was already there');
      expect(first.markersAdded, 2 + 1);

      final again = mergeInto(first.track,
          loops: PracticeSheet.fromTrack(track).rebasedFor(100000).loops,
          sets: PracticeSheet.fromTrack(track).rebasedFor(100000).sets);
      expect(again.loopsAdded, 0);
      expect(again.markersAdded, 0);
    });

    test('duration check allows small differences only', () {
      final sheet = PracticeSheet.fromTrack(track);
      expect(sheet.matchesDuration(100800), isTrue);
      expect(sheet.matchesDuration(130000), isFalse);
    });

    test('label text lists each mark segment in seconds', () {
      const t = Track(
        id: 't',
        title: 'x',
        fileName: 'x',
        durationMs: 10000,
        sizeBytes: 0,
        addedAtMs: 0,
        markerSets: [
          MarkerSet(id: 's', name: 'S', createdAtMs: 0, markers: [
            Marker(id: 'b', label: 'two', positionMs: 4500),
            Marker(id: 'a', label: 'one', positionMs: 1000),
            Marker(id: 'c', label: 'w', positionMs: 2000, tier: MarkerTier.minimark),
          ]),
        ],
      );
      expect(markersAsLabelText(t), '1.000\t4.500\tone\n4.500\t10.000\ttwo\n');
    });

    test('share file stems are safe', () {
      expect(shareFileStem('Surah / Lesson: 1?'), 'Surah_Lesson_1');
      expect(shareFileStem('???'), 'practice');
    });
  });

  group('marker export v2 (the file other apps read)', () {
    const track = Track(
      id: 't',
      title: 'surah 001',
      originalName: '001 Al-Fatiha.mp3',
      fileName: 't.mp3',
      durationMs: 60000,
      sizeBytes: 1,
      addedAtMs: 0,
      markerSets: [
        MarkerSet(id: 's', name: 'Reciter A', createdAtMs: 0, markers: [
          Marker(id: '2', label: '2', positionMs: 10000, skip: true),
          Marker(id: 'm', label: '1', positionMs: 6000, tier: MarkerTier.minimark),
          Marker(id: '1', label: '1', positionMs: 5000),
          Marker(id: 'n', label: '1', positionMs: 11000, tier: MarkerTier.minimark),
        ]),
      ],
      activeMarkerSetId: 's',
    );

    test('has the exact shape, key order and nesting of the original export', () {
      final export = MarkerSetExport.fromSet(track, track.activeSet!, contentHash: 'deadbeef');
      final json = export.toJson();
      expect(json.keys.toList(), ['formatVersion', 'audio', 'markers']);
      expect(json['formatVersion'], 2);
      expect((json['audio']! as Map).keys.toList(), ['displayName', 'durationMs', 'contentHash']);
      expect((json['audio']! as Map)['displayName'], '001 Al-Fatiha.mp3');
      final markers = json['markers']! as List;
      expect(markers.length, 2);
      final first = markers.first as Map;
      expect(first.keys.toList(), ['label', 'startMs', 'skip', 'minimarks']);
      expect((first['minimarks']! as List).single, {'label': '1', 'startMs': 6000, 'skip': false});
      expect((markers.last as Map)['skip'], isTrue);
      expect(((markers.last as Map)['minimarks']! as List).single['startMs'], 11000);
    });

    test('the hash is left out when unknown, like the original', () {
      final json = MarkerSetExport.fromSet(track, track.activeSet!).toJson();
      expect((json['audio']! as Map).containsKey('contentHash'), isFalse);
    });

    test('the text is pretty-printed JSON that parses back', () {
      final text = MarkerSetExport.fromSet(track, track.activeSet!).toJsonText();
      expect(text.contains('\n  "formatVersion": 2'), isTrue);
      expect(jsonDecode(text), isA<Map<String, Object?>>());
    });

    test('suggested file name is <audio>_<set>_timestamps.json', () {
      expect(MarkerSetExport.suggestedFileName(track, track.activeSet),
          '001_Al-Fatiha_mp3_Reciter_A_timestamps.json');
      expect(MarkerSetExport.suggestedFileName(track, null), '001_Al-Fatiha_mp3_timestamps.json');
    });

    test('AudioStorage computes a SHA-256', () async {
      final storage = AudioStorage(Directory(p.join(temp.path, 'audio')));
      await storage.ensureCreated();
      await storage.fileFor('a.mp3').writeAsString('abc');
      expect(await storage.sha256Of('a.mp3'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      await cleanUp();
    });
  });

  group('backup & restore', () {
    Track library(String id, String title, int duration, {String? hash, List<Loop> loops = const [], List<MarkerSet> sets = const []}) => Track(
          id: id,
          title: title,
          fileName: '$id.mp3',
          durationMs: duration,
          sizeBytes: 1,
          addedAtMs: 0,
          contentHash: hash,
          loops: loops,
          markerSets: sets,
        );

    final source = [
      library('a', 'Lesson 1', 60000, hash: 'h1', loops: const [
        Loop(id: 'a1', name: 'Hook', startMs: 1000, endMs: 5000, createdAtMs: 0),
        Loop(id: 'a2', name: 'Bridge', startMs: 10000, endMs: 15000, createdAtMs: 0, speed: 0.7),
      ], sets: const [
        MarkerSet(id: 'sa', name: 'Set 1', createdAtMs: 0, markers: [Marker(id: 'k', label: '1', positionMs: 2000)]),
      ]),
      library('b', 'Lesson 2', 90000),
    ];
    final routines = [
      Routine(id: 'r', name: 'Warm up', createdAtMs: 0, updatedAtMs: 0, rounds: 2, shuffle: true, steps: const [
        RoutineStep(id: 's1', trackId: 'a', loopId: 'a1', repeats: 4, pauseAfterMs: 1000, next: StepNext.goTo('s2')),
        RoutineStep(id: 's2', trackId: 'a', loopId: 'a2', repeats: 0),
        RoutineStep(id: 's3', trackId: 'b'),
      ]),
    ];

    test('round-trips through text', () {
      final bundle = BackupBundle.parse(BackupBundle.create(source, routines, nowMs: 5).toJsonText());
      expect(bundle.tracks.length, 2);
      expect(bundle.tracks.first.loops.length, 2);
      expect(bundle.routines.single.steps.length, 3);
      expect(bundle.routines.single.steps.first.step.next, const StepNext.goTo('s2'));
      expect(() => BackupBundle.parse('{"format":"x"}'), throwsA(isA<FormatException>()));
    });

    test('restores onto a fresh library by hash, or by name and length', () {
      final bundle = BackupBundle.create(source, routines);
      // New phone: same audio re-imported with new ids; the first has its hash, the second only matches by name.
      final fresh = [
        library('n1', 'something else', 60000, hash: 'h1'),
        library('n2', 'lesson 2', 90400),
        library('n3', 'Unrelated', 1000),
      ];
      final result = applyBackup(bundle, fresh, const []);
      expect(result.report.matchedTracks, 2);
      expect(result.report.unmatchedTitles, isEmpty);
      final n1 = result.tracks.firstWhere((t) => t.id == 'n1');
      expect(n1.loops.map((l) => l.name).toList(), ['Hook', 'Bridge']);
      expect(n1.markerSets.single.markers.single.positionMs, 2000);
      expect(result.report.loopsAdded, 2);
      expect(result.report.markersAdded, 1);

      final routine = result.routines.single;
      expect(routine.name, 'Warm up');
      expect((routine.rounds, routine.shuffle), (2, true));
      expect(routine.steps.map((s) => s.trackId).toList(), ['n1', 'n1', 'n2']);
      expect(routine.steps.map((s) => s.repeats).toList(), [4, 0, 3]);
      expect(routine.steps.first.pauseAfterMs, 1000);
      // The go-to still points at the right (re-identified) step.
      expect(routine.steps.first.next, StepNext.goTo(routine.steps[1].id));
      expect(routine.steps[1].loopId, n1.loops[1].id);
    });

    test('tracks missing from the library are reported, and their steps dropped', () {
      final bundle = BackupBundle.create(source, routines);
      final result = applyBackup(bundle, [library('n1', 'Lesson 1', 60000, hash: 'h1')], const []);
      expect(result.report.matchedTracks, 1);
      expect(result.report.unmatchedTitles, ['Lesson 2']);
      expect(result.report.stepsDropped, 1);
      expect(result.routines.single.steps.length, 2);
    });

    test('restoring twice changes nothing the second time', () {
      final bundle = BackupBundle.create(source, routines);
      final fresh = [library('n1', 'Lesson 1', 60000, hash: 'h1'), library('n2', 'Lesson 2', 90000)];
      final once = applyBackup(bundle, fresh, const []);
      final twice = applyBackup(bundle, once.tracks, once.routines);
      expect(twice.report.changedAnything, isFalse);
      expect(twice.routines.length, 1);
      expect(twice.tracks.firstWhere((t) => t.id == 'n1').loops.length, 2);
    });

    test('matching prefers the hash and refuses lengths that differ too much', () {
      const backup = BackupTrack(title: 'T', originalName: '', durationMs: 60000, contentHash: 'h', loops: [], markerSets: []);
      expect(matchTrack(backup, [library('x', 'other', 5, hash: 'h')])!.id, 'x');
      expect(matchTrack(backup, [library('y', 'T', 70000)]), isNull);
      expect(matchTrack(backup, [library('y', 'T', 61000)])!.id, 'y');
    });
  });
}

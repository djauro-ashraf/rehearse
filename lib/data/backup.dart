import 'dart:convert';

import '../core/ids.dart';
import '../core/json.dart';
import '../domain/loop.dart';
import '../domain/marker.dart';
import '../domain/routine.dart';
import '../domain/track.dart';
import 'practice_sheet.dart';

/// Everything you've built (loops, marker sets, routines) in one file, without
/// the audio itself. Restoring matches tracks by content hash, or by name and
/// length, so it works after a reinstall or on a new phone once the audio has
/// been imported again.
final class BackupBundle {
  const BackupBundle({
    required this.exportedAtMs,
    required this.tracks,
    required this.routines,
  });

  static const String formatId = 'rehearse.backup';
  static const int version = 1;

  factory BackupBundle.create(List<Track> tracks, List<Routine> routines, {int? nowMs}) {
    final indexOf = {for (var i = 0; i < tracks.length; i++) tracks[i].id: i};
    return BackupBundle(
      exportedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      tracks: [
        for (final t in tracks)
          BackupTrack(
            title: t.title,
            originalName: t.originalName,
            durationMs: t.durationMs,
            contentHash: t.contentHash,
            loops: t.loops,
            markerSets: t.markerSets,
          ),
      ],
      routines: [
        for (final r in routines)
          BackupRoutine(
            name: r.name,
            rounds: r.rounds,
            shuffle: r.shuffle,
            steps: [
              for (final s in r.steps)
                if (indexOf[s.trackId] != null)
                  BackupStep(trackIndex: indexOf[s.trackId]!, step: s),
            ],
          ),
      ],
    );
  }

  /// Throws [FormatException] if [text] isn't a Rehearse backup.
  factory BackupBundle.parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const FormatException('This file is not valid JSON.');
    }
    final map = asMap(decoded);
    if (asString(map['format']) != formatId) {
      throw const FormatException('This is not a Rehearse backup.');
    }
    return BackupBundle(
      exportedAtMs: asInt(map['exportedAtMs']),
      tracks: parseList(map['tracks'], BackupTrack.fromJson),
      routines: parseList(map['routines'], BackupRoutine.fromJson),
    );
  }

  final int exportedAtMs;
  final List<BackupTrack> tracks;
  final List<BackupRoutine> routines;

  String toJsonText() => const JsonEncoder.withIndent('  ').convert({
        'format': formatId,
        'version': version,
        'exportedAtMs': exportedAtMs,
        'tracks': [for (final t in tracks) t.toJson()],
        'routines': [for (final r in routines) r.toJson()],
      });
}

final class BackupTrack {
  const BackupTrack({
    required this.title,
    required this.originalName,
    required this.durationMs,
    required this.contentHash,
    required this.loops,
    required this.markerSets,
  });

  factory BackupTrack.fromJson(Map<String, Object?> json) => BackupTrack(
        title: asString(json['title'], 'Untitled'),
        originalName: asString(json['originalName']),
        durationMs: asInt(json['durationMs']),
        contentHash: asStringOrNull(json['contentHash']),
        loops: parseList(json['loops'], Loop.fromJson),
        markerSets: parseList(json['markerSets'], MarkerSet.fromJson),
      );

  final String title;
  final String originalName;
  final int durationMs;
  final String? contentHash;
  final List<Loop> loops;
  final List<MarkerSet> markerSets;

  Map<String, Object?> toJson() => {
        'title': title,
        'originalName': originalName,
        'durationMs': durationMs,
        'contentHash': contentHash,
        'loops': [for (final l in loops) l.toJson()],
        'markerSets': [for (final s in markerSets) s.toJson()],
      };
}

final class BackupStep {
  const BackupStep({required this.trackIndex, required this.step});

  factory BackupStep.fromJson(Map<String, Object?> json) => BackupStep(
        trackIndex: asInt(json['trackIndex'], -1),
        step: RoutineStep.fromJson(json),
      );

  final int trackIndex;
  final RoutineStep step;

  Map<String, Object?> toJson() => {...step.toJson(), 'trackIndex': trackIndex};
}

final class BackupRoutine {
  const BackupRoutine({
    required this.name,
    required this.rounds,
    required this.shuffle,
    required this.steps,
  });

  factory BackupRoutine.fromJson(Map<String, Object?> json) => BackupRoutine(
        name: asString(json['name'], 'Routine'),
        rounds: asInt(json['rounds'], 1).clamp(0, 99),
        shuffle: asBool(json['shuffle']),
        steps: parseList(json['steps'], BackupStep.fromJson),
      );

  final String name;
  final int rounds;
  final bool shuffle;
  final List<BackupStep> steps;

  Map<String, Object?> toJson() => {
        'name': name,
        'rounds': rounds,
        'shuffle': shuffle,
        'steps': [for (final s in steps) s.toJson()],
      };
}

/// What a restore did, for showing to the user.
final class RestoreReport {
  const RestoreReport({
    required this.matchedTracks,
    required this.unmatchedTitles,
    required this.loopsAdded,
    required this.markersAdded,
    required this.routinesAdded,
    required this.stepsDropped,
  });

  final int matchedTracks;

  /// Titles in the backup with no matching audio in the library yet.
  final List<String> unmatchedTitles;
  final int loopsAdded;
  final int markersAdded;
  final int routinesAdded;
  final int stepsDropped;

  bool get changedAnything => loopsAdded + markersAdded + routinesAdded > 0;
}

String _normalise(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0080-\uffff]+'), '');

/// Finds the library track a backed-up track belongs to: same content hash,
/// else same name and (nearly) the same length.
Track? matchTrack(BackupTrack backup, List<Track> library, {int toleranceMs = 1500}) {
  if (backup.contentHash != null) {
    for (final t in library) {
      if (t.contentHash == backup.contentHash) return t;
    }
  }
  Track? best;
  var bestDiff = toleranceMs + 1;
  for (final t in library) {
    final diff = (t.durationMs - backup.durationMs).abs();
    if (diff > toleranceMs) continue;
    final sameName = _normalise(t.title) == _normalise(backup.title) ||
        (backup.originalName.isNotEmpty &&
            _normalise(t.originalName) == _normalise(backup.originalName));
    if (sameName && diff < bestDiff) {
      best = t;
      bestDiff = diff;
    }
  }
  return best;
}

/// Applies [bundle] to the current library and routines. Pure: returns the new
/// lists and a report; nothing is written.
({List<Track> tracks, List<Routine> routines, RestoreReport report}) applyBackup(
  BackupBundle bundle,
  List<Track> library,
  List<Routine> routines,
) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final tracks = [...library];
  final unmatched = <String>[];
  var matched = 0;
  var loopsAdded = 0;
  var markersAdded = 0;

  // Per backed-up track: its library track id and old loop id → new loop id.
  final trackIds = <int, String>{};
  final loopIds = <int, Map<String, String>>{};

  for (var i = 0; i < bundle.tracks.length; i++) {
    final backup = bundle.tracks[i];
    final target = matchTrack(backup, tracks);
    if (target == null) {
      unmatched.add(backup.title);
      continue;
    }
    matched++;
    // Fresh ids, remembering which backed-up loop became which.
    final rebased = rebaseLoopsWithIds(backup.loops, target.durationMs, now);
    final byOld = {for (final (old, loop) in rebased) old: loop.id};
    final kept = [for (final (_, loop) in rebased) loop];
    final merged = mergeInto(
      target,
      loops: kept,
      sets: rebaseSets(backup.markerSets, target.durationMs, now),
    );
    loopsAdded += merged.loopsAdded;
    markersAdded += merged.markersAdded;
    final index = tracks.indexWhere((t) => t.id == target.id);
    tracks[index] = merged.track;
    trackIds[i] = target.id;
    loopIds[i] = {for (final e in byOld.entries) e.key: merged.loopIds[e.value] ?? e.value};
  }

  final result = [...routines];
  var routinesAdded = 0;
  var stepsDropped = 0;
  for (final backup in bundle.routines) {
    final newIds = {for (final s in backup.steps) s.step.id: newId()};
    final steps = <RoutineStep>[];
    for (final s in backup.steps) {
      final trackId = trackIds[s.trackIndex];
      final oldLoop = s.step.loopId;
      final loopId = oldLoop == null ? null : loopIds[s.trackIndex]?[oldLoop];
      if (trackId == null || (oldLoop != null && loopId == null)) {
        stepsDropped++;
        continue;
      }
      final next = s.step.next;
      steps.add(RoutineStep(
        id: newIds[s.step.id]!,
        trackId: trackId,
        loopId: loopId,
        repeats: s.step.repeats,
        pauseAfterMs: s.step.pauseAfterMs,
        next: next.kind == StepNextKind.goTo && newIds[next.stepId] != null
            ? StepNext.goTo(newIds[next.stepId]!)
            : (next.kind == StepNextKind.goTo ? const StepNext.next() : next),
      ));
    }
    if (steps.isEmpty) continue;
    String signature(String name, List<RoutineStep> list) => '$name|${[
          for (final s in list) '${s.trackId}/${s.loopId}/${s.repeats}/${s.pauseAfterMs}',
        ].join(',')}';
    final candidate = signature(backup.name, steps);
    if (result.any((r) => signature(r.name, r.steps) == candidate)) continue;
    result.insert(
      0,
      Routine(
        id: newId(),
        name: backup.name,
        createdAtMs: now,
        updatedAtMs: now,
        steps: steps,
        rounds: backup.rounds,
        shuffle: backup.shuffle,
      ),
    );
    routinesAdded++;
  }

  return (
    tracks: tracks,
    routines: result,
    report: RestoreReport(
      matchedTracks: matched,
      unmatchedTitles: unmatched,
      loopsAdded: loopsAdded,
      markersAdded: markersAdded,
      routinesAdded: routinesAdded,
      stepsDropped: stepsDropped,
    ),
  );
}

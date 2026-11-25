import 'dart:convert';

import '../core/ids.dart';
import '../core/json.dart';
import '../domain/loop.dart';
import '../domain/loop_rules.dart';
import '../domain/marker.dart';
import '../domain/segments.dart';
import '../domain/track.dart';

/// Adds [loops] and [sets] to [track], skipping what is already there:
/// a loop with the same start/end, a marker at the same spot and level, and
/// merging into an existing marker set of the same name.
///
/// Incoming items must already have fresh ids. Returns the updated track,
/// how many loops/markers were really added, and a map from each incoming loop
/// id to the id it ended up with (the existing duplicate's id, or its own).
({Track track, int loopsAdded, int markersAdded, Map<String, String> loopIds})
    mergeInto(
  Track track, {
  required List<Loop> loops,
  required List<MarkerSet> sets,
}) {
  final ids = <String, String>{};
  final mergedLoops = [...track.loops];
  var loopsAdded = 0;
  for (final loop in loops) {
    final existing = mergedLoops
        .where((l) => l.startMs == loop.startMs && l.endMs == loop.endMs)
        .firstOrNull;
    if (existing != null) {
      ids[loop.id] = existing.id;
    } else {
      mergedLoops.add(loop);
      ids[loop.id] = loop.id;
      loopsAdded++;
    }
  }

  final mergedSets = [...track.markerSets];
  var markersAdded = 0;
  for (final incoming in sets) {
    final index = mergedSets.indexWhere(
      (s) => s.name.toLowerCase() == incoming.name.toLowerCase(),
    );
    if (index < 0) {
      mergedSets.add(incoming);
      markersAdded += incoming.markers.length;
      continue;
    }
    final target = mergedSets[index];
    final taken = {for (final m in target.markers) (m.positionMs, m.tier)};
    final fresh = [
      for (final m in incoming.markers)
        if (!taken.contains((m.positionMs, m.tier))) m,
    ];
    markersAdded += fresh.length;
    mergedSets[index] = target.copyWith(markers: [...target.markers, ...fresh]);
  }

  return (
    track: track.copyWith(
      loops: mergedLoops,
      markerSets: mergedSets,
      activeMarkerSetId: track.activeMarkerSetId ??
          (mergedSets.isEmpty ? null : mergedSets.first.id),
    ),
    loopsAdded: loopsAdded,
    markersAdded: markersAdded,
    loopIds: ids,
  );
}

/// A portable file holding the loops and marker sets of one track, so a
/// teacher, a friend, or another device can load them onto the same audio.
final class PracticeSheet {
  const PracticeSheet({
    required this.title,
    required this.durationMs,
    required this.loops,
    required this.markerSets,
  });

  static const String formatId = 'rehearse.sheet';
  static const int version = 2;

  factory PracticeSheet.fromTrack(Track track) => PracticeSheet(
        title: track.title,
        durationMs: track.durationMs,
        loops: track.loops,
        markerSets: track.markerSets,
      );

  /// Throws [FormatException] if [text] isn't a practice sheet. Version 1
  /// sheets (a flat marker list) are read as a single marker set.
  factory PracticeSheet.parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const FormatException('This file is not valid JSON.');
    }
    final map = asMap(decoded);
    if (asString(map['format']) != formatId) {
      throw const FormatException('This is not a Rehearse practice sheet.');
    }
    final audio = asMap(map['audio']);
    var sets = parseList(map['markerSets'], MarkerSet.fromJson);
    final legacy = parseList(map['markers'], Marker.fromJson);
    if (sets.isEmpty && legacy.isNotEmpty) {
      sets = [
        MarkerSet(id: newId(), name: 'Set 1', createdAtMs: 0, markers: legacy),
      ];
    }
    return PracticeSheet(
      title: asString(audio['title'], 'Untitled'),
      durationMs: asInt(audio['durationMs']),
      loops: parseList(map['loops'], Loop.fromJson),
      markerSets: sets,
    );
  }

  final String title;
  final int durationMs;
  final List<Loop> loops;
  final List<MarkerSet> markerSets;

  String toJsonText() => const JsonEncoder.withIndent('  ').convert({
        'format': formatId,
        'version': version,
        'audio': {'title': title, 'durationMs': durationMs},
        'loops': [for (final l in loops) l.toJson()],
        'markerSets': [for (final s in markerSets) s.toJson()],
      });

  /// Whether the sheet was made for audio of (about) the same length.
  bool matchesDuration(int otherMs, {int toleranceMs = 1500}) =>
      durationMs <= 0 || (durationMs - otherMs).abs() <= toleranceMs;

  /// Loops and marker sets re-identified and clamped to [durationMs], ready
  /// to be merged into a track without clashing with what it already has.
  ({List<Loop> loops, List<MarkerSet> sets}) rebasedFor(int durationMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (loops: rebaseLoops(loops, durationMs, now), sets: rebaseSets(markerSets, durationMs, now));
  }
}

/// Fresh ids, regions clamped to the audio; loops that don't fit are dropped.
/// Each result is paired with the id of the loop it came from.
List<(String, Loop)> rebaseLoopsWithIds(List<Loop> loops, int durationMs, int nowMs) => [
      for (final loop in loops)
        if (LoopRules.region(loop.startMs, loop.endMs, durationMs)
            case (final start, final end))
          (
            loop.id,
            Loop(
              id: newId(),
              name: loop.name,
              startMs: start,
              endMs: end,
              createdAtMs: nowMs,
              speed: loop.speed,
              pitch: loop.pitch,
              repeats: loop.repeats,
              gap: loop.gap,
            ),
          ),
    ];

List<Loop> rebaseLoops(List<Loop> loops, int durationMs, int nowMs) => [
      for (final (_, loop) in rebaseLoopsWithIds(loops, durationMs, nowMs)) loop,
    ];

/// Fresh ids; markers past the end of the audio are dropped.
List<MarkerSet> rebaseSets(List<MarkerSet> sets, int durationMs, int nowMs) => [
      for (final set in sets)
        MarkerSet(
          id: newId(),
          name: set.name,
          createdAtMs: nowMs,
          lockedMarks: set.lockedMarks,
          lockedMinimarks: set.lockedMinimarks,
          markers: [
            for (final m in set.markers)
              if (m.positionMs < durationMs)
                Marker(
                  id: newId(),
                  label: m.label,
                  positionMs: m.positionMs,
                  tier: m.tier,
                  skip: m.skip,
                ),
          ],
        ),
    ];

/// Plain-text label track (`start<TAB>end<TAB>label`, seconds), the format
/// Audacity and many annotation tools import. Lists the active set's Marks.
String markersAsLabelText(Track track) {
  final buffer = StringBuffer();
  String seconds(int ms) => (ms / 1000).toStringAsFixed(3);
  for (final segment in buildSegments(track.markers, track.durationMs)) {
    buffer.writeln(
      '${seconds(segment.startMs)}\t${seconds(segment.endMs)}\t${segment.mark.label}',
    );
  }
  return buffer.toString();
}

/// A safe file name stem for sharing.
String shareFileStem(String title) {
  final cleaned = title.replaceAll(RegExp(r'[^\w\- ]+', unicode: true), '').trim();
  return cleaned.isEmpty ? 'practice' : cleaned.replaceAll(RegExp(r'\s+'), '_');
}

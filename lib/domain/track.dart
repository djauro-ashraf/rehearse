import '../core/json.dart';
import 'gap.dart';
import 'loop.dart';
import 'loop_rules.dart';
import 'marker.dart';

/// Where you left off on a track, so reopening it restores the exact setup.
final class PracticeMemory {
  const PracticeMemory({
    this.positionMs = 0,
    this.speed = 1.0,
    this.pitch = 0.0,
    this.loopStartMs,
    this.loopEndMs,
    this.loopOn = false,
    this.repeats = 0,
    this.gap = const Gap.none(),
    this.activeLoopId,
  });

  factory PracticeMemory.fromJson(Map<String, Object?> json) => PracticeMemory(
        positionMs: asInt(json['positionMs']).clamp(0, 1 << 40),
        speed: LoopRules.clampSpeed(asDouble(json['speed'], 1.0)),
        pitch: LoopRules.clampPitch(asDouble(json['pitch'])),
        loopStartMs: asIntOrNull(json['loopStartMs']),
        loopEndMs: asIntOrNull(json['loopEndMs']),
        loopOn: asBool(json['loopOn']),
        repeats: LoopRules.clampRepeats(asInt(json['repeats'])),
        gap: Gap.fromJson(json['gap']),
        activeLoopId: asStringOrNull(json['activeLoopId']),
      );

  final int positionMs;
  final double speed;
  final double pitch;
  final int? loopStartMs;
  final int? loopEndMs;
  final bool loopOn;
  final int repeats;
  final Gap gap;
  final String? activeLoopId;

  bool get hasLoop => loopStartMs != null && loopEndMs != null;

  PracticeMemory copyWith({
    int? positionMs,
    double? speed,
    double? pitch,
    int? loopStartMs,
    int? loopEndMs,
    bool? loopOn,
    int? repeats,
    Gap? gap,
    String? activeLoopId,
    bool clearLoop = false,
    bool clearActiveLoop = false,
  }) =>
      PracticeMemory(
        positionMs: positionMs ?? this.positionMs,
        speed: speed ?? this.speed,
        pitch: pitch ?? this.pitch,
        loopStartMs: clearLoop ? null : loopStartMs ?? this.loopStartMs,
        loopEndMs: clearLoop ? null : loopEndMs ?? this.loopEndMs,
        loopOn: clearLoop ? false : loopOn ?? this.loopOn,
        repeats: repeats ?? this.repeats,
        gap: gap ?? this.gap,
        activeLoopId:
            clearActiveLoop ? null : activeLoopId ?? this.activeLoopId,
      );

  Map<String, Object?> toJson() => {
        'positionMs': positionMs,
        'speed': speed,
        'pitch': pitch,
        'loopStartMs': loopStartMs,
        'loopEndMs': loopEndMs,
        'loopOn': loopOn,
        'repeats': repeats,
        'gap': gap.toJson(),
        'activeLoopId': activeLoopId,
      };
}

/// One imported audio file together with everything you've built around it.
final class Track {
  const Track({
    required this.id,
    required this.title,
    required this.fileName,
    required this.durationMs,
    required this.sizeBytes,
    required this.addedAtMs,
    this.lastPlayedAtMs = 0,
    this.memory = const PracticeMemory(),
    this.loops = const [],
    this.markerSets = const [],
    this.activeMarkerSetId,
    this.originalName = '',
    this.contentHash,
  });

  factory Track.fromJson(Map<String, Object?> json) {
    var sets = parseList(json['markerSets'], MarkerSet.fromJson);
    final legacy = parseList(json['markers'], Marker.fromJson);
    if (sets.isEmpty && legacy.isNotEmpty) {
      sets = [
        MarkerSet(
          id: 'set-legacy',
          name: 'Set 1',
          createdAtMs: asInt(json['addedAtMs']),
          markers: legacy,
        ),
      ];
    }
    return Track(
        id: asString(json['id']),
        title: asString(json['title'], 'Untitled'),
        fileName: asString(json['fileName']),
        durationMs: asInt(json['durationMs']),
        sizeBytes: asInt(json['sizeBytes']),
        addedAtMs: asInt(json['addedAtMs']),
        lastPlayedAtMs: asInt(json['lastPlayedAtMs']),
        memory: PracticeMemory.fromJson(asMap(json['memory'])),
        loops: parseList(json['loops'], Loop.fromJson),
        markerSets: sets,
        activeMarkerSetId: asStringOrNull(json['activeMarkerSetId']),
        originalName: asString(json['originalName']),
        contentHash: asStringOrNull(json['contentHash']),
      );
  }

  final String id;
  final String title;

  /// File name inside the app's audio folder (never a full path, so the
  /// library survives the app's storage location changing).
  final String fileName;
  final int durationMs;
  final int sizeBytes;
  final int addedAtMs;
  final int lastPlayedAtMs;
  final PracticeMemory memory;
  final List<Loop> loops;

  /// Named stamping passes. Empty until the first marker is added.
  final List<MarkerSet> markerSets;
  final String? activeMarkerSetId;

  /// The file name as it was imported (e.g. `001.mp3`), used in exports.
  final String originalName;

  /// SHA-256 of the audio, computed the first time it is needed.
  final String? contentHash;

  bool get hasBeenPlayed => lastPlayedAtMs > 0;

  /// The marker set being worked on (the first one if none is selected).
  MarkerSet? get activeSet {
    if (markerSets.isEmpty) return null;
    for (final set in markerSets) {
      if (set.id == activeMarkerSetId) return set;
    }
    return markerSets.first;
  }

  /// Markers of the active set.
  List<Marker> get markers => activeSet?.markers ?? const [];

  /// The name shown in exports: the original file name, else the title.
  String get exportName => originalName.isNotEmpty ? originalName : title;

  Loop? loopById(String? id) {
    if (id == null) return null;
    for (final loop in loops) {
      if (loop.id == id) return loop;
    }
    return null;
  }

  Track copyWith({
    String? title,
    int? durationMs,
    int? lastPlayedAtMs,
    PracticeMemory? memory,
    List<Loop>? loops,
    List<MarkerSet>? markerSets,
    String? activeMarkerSetId,
    String? contentHash,
  }) =>
      Track(
        id: id,
        title: title ?? this.title,
        fileName: fileName,
        durationMs: durationMs ?? this.durationMs,
        sizeBytes: sizeBytes,
        addedAtMs: addedAtMs,
        lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
        memory: memory ?? this.memory,
        loops: loops ?? this.loops,
        markerSets: markerSets ?? this.markerSets,
        activeMarkerSetId: activeMarkerSetId ?? this.activeMarkerSetId,
        originalName: originalName,
        contentHash: contentHash ?? this.contentHash,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'fileName': fileName,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'addedAtMs': addedAtMs,
        'lastPlayedAtMs': lastPlayedAtMs,
        'memory': memory.toJson(),
        'loops': [for (final l in loops) l.toJson()],
        'markerSets': [for (final s in markerSets) s.toJson()],
        'activeMarkerSetId': activeMarkerSetId,
        'originalName': originalName,
        'contentHash': contentHash,
      };
}

import 'dart:convert';

import '../domain/marker.dart';
import '../domain/segments.dart';
import '../domain/track.dart';

/// The portable, app-agnostic marker file (format version 2) that other apps
/// can read: each Mark with the Minimarks nested inside it. Segment N runs from
/// its `startMs` to the next entry's `startMs` (or the end of the audio).
/// `skip` marks a segment that should not count as real content, though its
/// timestamp still bounds the segment before it. Field names and order match
/// the original A Drill export exactly.
final class MarkerSetExport {
  const MarkerSetExport({
    required this.displayName,
    required this.durationMs,
    required this.markers,
    this.contentHash,
  });

  static const int formatVersion = 2;

  factory MarkerSetExport.fromSet(
    Track track,
    MarkerSet set, {
    String? contentHash,
  }) =>
      MarkerSetExport(
        displayName: track.exportName,
        durationMs: track.durationMs,
        contentHash: contentHash ?? track.contentHash,
        markers: [
          for (final segment in buildSegments(set.markers, track.durationMs))
            MarkerRef(
              label: segment.mark.label,
              startMs: segment.mark.positionMs,
              skip: segment.mark.skip,
              minimarks: [
                for (final m in segment.minimarks)
                  MinimarkRef(label: m.label, startMs: m.positionMs, skip: m.skip),
              ],
            ),
        ],
      );

  final String displayName;
  final int durationMs;

  /// SHA-256 of the audio, so a consumer can confirm the file matches.
  final String? contentHash;
  final List<MarkerRef> markers;

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'audio': {
          'displayName': displayName,
          'durationMs': durationMs,
          if (contentHash != null) 'contentHash': contentHash,
        },
        'markers': [for (final m in markers) m.toJson()],
      };

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// `<audio>_<set>_timestamps.json`, safe for any file system.
  static String suggestedFileName(Track track, MarkerSet? set) {
    String clean(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final name = clean(track.exportName);
    return set == null
        ? '${name}_timestamps.json'
        : '${name}_${clean(set.name)}_timestamps.json';
  }
}

final class MarkerRef {
  const MarkerRef({
    required this.label,
    required this.startMs,
    required this.skip,
    required this.minimarks,
  });

  final String label;
  final int startMs;
  final bool skip;
  final List<MinimarkRef> minimarks;

  Map<String, Object?> toJson() => {
        'label': label,
        'startMs': startMs,
        'skip': skip,
        'minimarks': [for (final m in minimarks) m.toJson()],
      };
}

final class MinimarkRef {
  const MinimarkRef({
    required this.label,
    required this.startMs,
    required this.skip,
  });

  final String label;
  final int startMs;
  final bool skip;

  Map<String, Object?> toJson() =>
      {'label': label, 'startMs': startMs, 'skip': skip};
}

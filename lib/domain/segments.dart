import 'marker.dart';

/// One Mark's segment: its own bounds plus the Minimarks that fall inside it.
final class MarkSegment {
  const MarkSegment({
    required this.index,
    required this.mark,
    required this.endMs,
    this.minimarks = const [],
  });

  final int index;
  final Marker mark;
  final int endMs;

  /// Sorted by time.
  final List<Marker> minimarks;

  int get startMs => mark.positionMs;
  int get lengthMs => endMs - startMs;

  /// End of the sub-segment that starts at `minimarks[i]`: the next Minimark,
  /// or the end of this segment.
  int minimarkEndMs(int i) =>
      i + 1 < minimarks.length ? minimarks[i + 1].positionMs : endMs;
}

/// Markers sorted by time.
List<Marker> sortedMarkers(List<Marker> markers) =>
    [...markers]..sort((a, b) => a.positionMs.compareTo(b.positionMs));

/// Groups a flat marker list into Mark segments, each carrying the Minimarks
/// inside it. Computed from timestamps every time (never from stored parent
/// ids), so Minimarks re-home themselves when Marks are added or deleted. A
/// Minimark before the first Mark belongs to no segment, but is kept: it
/// reappears when an earlier Mark exists again.
List<MarkSegment> buildSegments(List<Marker> markers, int durationMs) {
  final marks = sortedMarkers([
    for (final m in markers)
      if (m.tier == MarkerTier.mark) m,
  ]);
  final minis = sortedMarkers([
    for (final m in markers)
      if (m.tier == MarkerTier.minimark) m,
  ]);
  return [
    for (var i = 0; i < marks.length; i++)
      () {
        final end = i + 1 < marks.length ? marks[i + 1].positionMs : durationMs;
        return MarkSegment(
          index: i,
          mark: marks[i],
          endMs: end,
          minimarks: [
            for (final m in minis)
              if (m.positionMs >= marks[i].positionMs && m.positionMs < end) m,
          ],
        );
      }(),
  ];
}

/// Index of the Mark segment containing [positionMs], or -1 before the first
/// Mark.
int segmentIndexAt(List<MarkSegment> segments, int positionMs) {
  for (var i = segments.length - 1; i >= 0; i--) {
    if (positionMs >= segments[i].startMs) return i;
  }
  return -1;
}

/// The segment a new Minimark at [positionMs] would nest in, or null before
/// the first Mark.
MarkSegment? enclosingSegment(
  List<Marker> markers,
  int positionMs,
  int durationMs,
) {
  final segments = buildSegments(markers, durationMs);
  final index = segmentIndexAt(segments, positionMs);
  return index < 0 ? null : segments[index];
}

/// The markers a new stamp of [tier] at [positionMs] is numbered against:
/// every Mark, or only the Minimarks inside the enclosing segment (so
/// numbering restarts per segment).
List<Marker> stampSiblings(
  MarkerTier tier,
  List<Marker> markers,
  int positionMs,
  int durationMs,
) {
  if (tier == MarkerTier.mark) {
    return [
      for (final m in markers)
        if (m.tier == MarkerTier.mark) m,
    ];
  }
  return enclosingSegment(markers, positionMs, durationMs)?.minimarks ?? const [];
}

/// The label a new stamp gets. Appending after the last sibling (listening
/// through in order) numbers it; inserting earlier than the last sibling
/// leaves it blank so the caller can ask for a name instead of guessing and
/// clashing with labels that were already renamed. Existing siblings are
/// never renumbered.
({String label, bool needsName}) stampLabel(
  List<Marker> siblings,
  int positionMs,
) {
  final sorted = sortedMarkers(siblings);
  final append = sorted.isEmpty || positionMs >= sorted.last.positionMs;
  return (label: append ? '${sorted.length + 1}' : '', needsName: !append);
}

import '../core/json.dart';

/// MARK = a top-level boundary (a verse, a phrase, a chapter). MINIMARK = a
/// finer boundary inside one Mark's segment (a word inside that verse).
enum MarkerTier { mark, minimark }

/// A labelled point in a track. A marker has no end of its own: markers split
/// a track into segments, each running from its marker to the next one of the
/// same level (or to the end of the enclosing segment / audio).
final class Marker {
  const Marker({
    required this.id,
    required this.label,
    required this.positionMs,
    this.tier = MarkerTier.mark,
    this.skip = false,
  });

  factory Marker.fromJson(Map<String, Object?> json) => Marker(
        id: asString(json['id']),
        label: asString(json['label']),
        positionMs: asInt(json['positionMs']).clamp(0, 1 << 40),
        tier: MarkerTier.values.firstWhere(
          (t) => t.name == asString(json['tier']),
          orElse: () => MarkerTier.mark,
        ),
        skip: asBool(json['skip']),
      );

  final String id;
  final String label;
  final int positionMs;
  final MarkerTier tier;

  /// The segment that starts here should not count as real content (for
  /// example a reciter repeating a verse). The timestamp still bounds the
  /// segment before it.
  final bool skip;

  Marker copyWith({String? label, int? positionMs, bool? skip}) => Marker(
        id: id,
        label: label ?? this.label,
        positionMs: positionMs ?? this.positionMs,
        tier: tier,
        skip: skip ?? this.skip,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'positionMs': positionMs,
        'tier': tier.name,
        'skip': skip,
      };
}

/// One named stamping pass over a track (for example two different readers of
/// the same recording). Each set can lock its Marks and Minimarks separately,
/// so a finished pass is safe from a stray tap while another is in progress.
final class MarkerSet {
  const MarkerSet({
    required this.id,
    required this.name,
    required this.createdAtMs,
    this.markers = const [],
    this.lockedMarks = false,
    this.lockedMinimarks = false,
  });

  factory MarkerSet.fromJson(Map<String, Object?> json) => MarkerSet(
        id: asString(json['id']),
        name: asString(json['name'], 'Set 1'),
        createdAtMs: asInt(json['createdAtMs']),
        markers: parseList(json['markers'], Marker.fromJson),
        lockedMarks: asBool(json['lockedMarks']),
        lockedMinimarks: asBool(json['lockedMinimarks']),
      );

  final String id;
  final String name;
  final int createdAtMs;
  final List<Marker> markers;
  final bool lockedMarks;
  final bool lockedMinimarks;

  bool isLocked(MarkerTier tier) =>
      tier == MarkerTier.mark ? lockedMarks : lockedMinimarks;

  int count(MarkerTier tier) => markers.where((m) => m.tier == tier).length;

  MarkerSet copyWith({
    String? name,
    List<Marker>? markers,
    bool? lockedMarks,
    bool? lockedMinimarks,
  }) =>
      MarkerSet(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        markers: markers ?? this.markers,
        lockedMarks: lockedMarks ?? this.lockedMarks,
        lockedMinimarks: lockedMinimarks ?? this.lockedMinimarks,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAtMs': createdAtMs,
        'markers': [for (final m in markers) m.toJson()],
        'lockedMarks': lockedMarks,
        'lockedMinimarks': lockedMinimarks,
      };
}

/// Tolerant JSON readers. Stored data may come from an older app version or a
/// hand-edited backup, so every reader falls back instead of throwing.
library;

int asInt(Object? v, [int fallback = 0]) => v is num ? v.round() : fallback;

int? asIntOrNull(Object? v) => v is num ? v.round() : null;

double asDouble(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

bool asBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

String asString(Object? v, [String fallback = '']) =>
    v is String ? v : fallback;

String? asStringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

Map<String, Object?> asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};

List<Object?> asList(Object? v) => v is List ? v : const [];

/// Maps every map entry of a JSON list through [parse], skipping junk.
List<T> parseList<T>(Object? v, T Function(Map<String, Object?>) parse) => [
      for (final item in asList(v))
        if (item is Map) parse(asMap(item)),
    ];

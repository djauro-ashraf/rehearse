/// Formats a duration in milliseconds as `m:ss`, `h:mm:ss`, or with tenths.
String formatMs(int ms, {bool tenths = false}) {
  final safe = ms < 0 ? 0 : ms;
  final totalSeconds = safe ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  final base = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  if (!tenths) return base;
  return '$base.${(safe % 1000) ~/ 100}';
}

/// Parses `83`, `83.5`, `1:23`, `1:23.4` or `1:02:03.5` into milliseconds.
/// Returns null when the text isn't a valid time.
int? parseTime(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length > 3) return null;
  var seconds = 0.0;
  for (final part in parts) {
    final value = double.tryParse(part);
    if (value == null || value < 0) return null;
    seconds = seconds * 60 + value;
  }
  return (seconds * 1000).round();
}

String formatSpeed(double speed) {
  final text = speed.toStringAsFixed(2);
  final trimmed =
      text.endsWith('0') ? text.substring(0, text.length - 1) : text;
  return '$trimmed×';
}

String formatPitch(double semitones) {
  final value = semitones.round();
  if (value == 0) return '0 st';
  return '${value > 0 ? '+' : '−'}${value.abs()} st';
}

/// `1.5 s`, `45 s`, `2 min 5 s` – used for gaps and routine estimates.
String formatSeconds(int ms) {
  final totalTenths = (ms / 100).round();
  if (totalTenths < 600) {
    final seconds = totalTenths / 10;
    final text = seconds == seconds.roundToDouble()
        ? seconds.toInt().toString()
        : seconds.toStringAsFixed(1);
    return '$text s';
  }
  final totalSeconds = (ms / 1000).round();
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return s == 0 ? '$m min' : '$m min $s s';
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// "just now", "5 min ago", "3 h ago", "yesterday", "12 days ago", "Mar 4".
String formatAgo(int thenMs, {int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final diff = now - thenMs;
  if (diff < 60 * 1000) return 'just now';
  if (diff < 3600 * 1000) return '${diff ~/ (60 * 1000)} min ago';
  if (diff < 24 * 3600 * 1000) return '${diff ~/ (3600 * 1000)} h ago';
  final days = diff ~/ (24 * 3600 * 1000);
  if (days == 1) return 'yesterday';
  if (days < 31) return '$days days ago';
  final date = DateTime.fromMillisecondsSinceEpoch(thenMs);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

/// Case-insensitive "natural" ordering, so `Lesson 2` sorts before `Lesson 10`
/// and `002.mp3` before `010.mp3`.
int naturalCompare(String a, String b) {
  final left = RegExp(r'(\d+|\D+)').allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = RegExp(r'(\d+|\D+)').allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final result = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}

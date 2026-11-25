import 'dart:math';

final Random _random = Random();

/// A short, sortable, collision-resistant id (time + randomness).
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = _random.nextInt(1 << 32).toRadixString(36).padLeft(6, '0');
  return '$time$salt';
}

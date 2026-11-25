import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Where imported audio lives. Files are copied in once, so the library keeps
/// working when the original is moved, deleted, or was only a temporary copy
/// handed over by another app.
class AudioStorage {
  AudioStorage(this.directory);

  final Directory directory;

  Future<void> ensureCreated() => directory.create(recursive: true);

  File fileFor(String fileName) => File(p.join(directory.path, fileName));

  String pathFor(String fileName) => fileFor(fileName).path;

  Future<bool> exists(String fileName) => fileFor(fileName).exists();

  Future<void> delete(String fileName) async {
    try {
      final file = fileFor(fileName);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// SHA-256 of the file as lowercase hex (streamed, so large files are fine).
  Future<String> sha256Of(String fileName) async {
    final digest = await sha256.bind(fileFor(fileName).openRead()).first;
    return digest.toString();
  }

  Future<int> totalBytes() async {
    var total = 0;
    if (!await directory.exists()) return 0;
    await for (final entity in directory.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}

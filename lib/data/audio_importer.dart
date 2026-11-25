import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/ids.dart';
import '../domain/track.dart';
import 'audio_storage.dart';

/// Something to import: a file on disk or a byte stream, plus its name.
final class ImportSource {
  const ImportSource({
    required this.name,
    this.path,
    this.openRead,
    this.isTemporary = false,
  });

  /// Original file name, e.g. `Lesson 3.mp3`.
  final String name;
  final String? path;
  final Stream<List<int>> Function()? openRead;

  /// True when [path] is a throw-away copy (a picker's cache file); it is
  /// deleted after import. Never true for the user's own files.
  final bool isTemporary;
}

/// Returns the duration in ms, or null if the file isn't playable audio.
typedef DurationProbe = Future<int?> Function(String path);

/// Copies audio into [AudioStorage] and turns it into a [Track].
class AudioImporter {
  AudioImporter({required this.storage, required this.probe});

  final AudioStorage storage;
  final DurationProbe probe;

  /// Returns null when the file can't be read or isn't audio.
  Future<Track?> import(ImportSource source) async {
    await storage.ensureCreated();
    final id = newId();
    final extension = _extensionOf(source.name);
    final fileName = '$id$extension';
    final destination = storage.fileFor(fileName);
    try {
      if (source.path != null) {
        await File(source.path!).copy(destination.path);
      } else if (source.openRead != null) {
        final sink = destination.openWrite();
        await sink.addStream(source.openRead!());
        await sink.close();
      } else {
        return null;
      }
      final durationMs = await probe(destination.path);
      if (durationMs == null || durationMs <= 0) {
        await storage.delete(fileName);
        return null;
      }
      return Track(
        id: id,
        title: titleFromFileName(source.name),
        originalName: source.name,
        fileName: fileName,
        durationMs: durationMs,
        sizeBytes: await destination.length(),
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      await storage.delete(fileName);
      return null;
    } finally {
      if (source.isTemporary && source.path != null) {
        try {
          await File(source.path!).delete();
        } catch (_) {}
      }
    }
  }

  static String _extensionOf(String name) {
    final ext = p.extension(name).toLowerCase();
    final valid = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext);
    return valid ? ext : '.audio';
  }
}

/// `my_lesson-03.mp3` → `my lesson-03`.
String titleFromFileName(String fileName) {
  final base = p.basenameWithoutExtension(fileName);
  final cleaned = base.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? 'Untitled' : cleaned;
}

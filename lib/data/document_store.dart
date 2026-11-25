import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Small JSON documents (library, routines, settings) with debounced, atomic
/// writes. The app never blocks on disk and a crash can't leave a half-written
/// file behind.
abstract interface class DocumentStore {
  /// Returns the stored document, or null if there is none (or it is corrupt).
  Future<Map<String, Object?>?> read(String name);

  /// Schedules [json] to be saved soon. Later writes to the same [name]
  /// replace earlier pending ones.
  void write(String name, Map<String, Object?> json);

  /// Writes everything that is still pending.
  Future<void> flush();
}

class FileDocumentStore implements DocumentStore {
  FileDocumentStore(
    this.directory, {
    this.debounce = const Duration(milliseconds: 600),
  });

  final Directory directory;
  final Duration debounce;

  final Map<String, Map<String, Object?>> _pending = {};
  Timer? _timer;
  Future<void> _queue = Future<void>.value();

  File _file(String name) => File(p.join(directory.path, '$name.json'));

  @override
  Future<Map<String, Object?>?> read(String name) async {
    final file = _file(name);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // Fall through: keep the broken file for inspection, start fresh.
    }
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename(p.join(directory.path, '$name.corrupt-$stamp.json'));
    } catch (_) {}
    return null;
  }

  @override
  void write(String name, Map<String, Object?> json) {
    _pending[name] = json;
    _timer ??= Timer(debounce, () => unawaited(flush()));
  }

  @override
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final batch = Map<String, Map<String, Object?>>.of(_pending);
    _pending.clear();
    _queue = _queue.then((_) async {
      for (final entry in batch.entries) {
        await _writeAtomically(entry.key, entry.value);
      }
    });
    return _queue;
  }

  Future<void> _writeAtomically(String name, Map<String, Object?> json) async {
    try {
      await directory.create(recursive: true);
      final target = _file(name);
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(json), flush: true);
      await temp.rename(target.path);
    } catch (_) {
      // Disk full / permissions: keep the app usable; the next change retries.
    }
  }
}

/// In-memory store for tests.
class MemoryDocumentStore implements DocumentStore {
  final Map<String, Map<String, Object?>> documents = {};

  @override
  Future<Map<String, Object?>?> read(String name) async => documents[name];

  @override
  void write(String name, Map<String, Object?> json) {
    // Round-trip through JSON so tests see exactly what a file would hold.
    documents[name] = (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();
  }

  @override
  Future<void> flush() async {}
}

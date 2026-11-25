import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audio_importer.dart';
import '../data/backup.dart';
import '../data/marker_export.dart';
import '../data/practice_sheet.dart';
import '../domain/track.dart';
import 'app_providers.dart';
import 'platform_providers.dart';
import 'library_notifier.dart';
import 'practice_controller.dart';
import 'routine_controller.dart';
import 'routines_notifier.dart';

final class ImportResult {
  const ImportResult({required this.added, required this.failed});

  final List<Track> added;
  final int failed;
}

/// Library-level operations that touch several parts of the app at once.
class TrackActions {
  TrackActions(this._ref);

  final Ref _ref;

  /// Opens the file picker and imports whatever the user chooses.
  Future<ImportResult> pickAndImport() async {
    final sources = await _ref.read(fileServiceProvider).pickAudio();
    return importSources(sources);
  }

  Future<ImportResult> importSources(List<ImportSource> sources) async {
    final importer = _ref.read(audioImporterProvider);
    final library = _ref.read(libraryProvider.notifier);
    final added = <Track>[];
    var failed = 0;
    for (final source in sources) {
      final track = await importer.import(source);
      if (track == null) {
        failed++;
      } else {
        library.add(track);
        added.add(track);
      }
    }
    return ImportResult(added: added, failed: failed);
  }

  /// Deletes a track, its audio file, and every routine step that used it.
  Future<void> deleteTrack(Track track) async {
    final engine = _ref.read(engineProvider);
    if (engine.state.trackId == track.id) {
      await _ref.read(routineControllerProvider.notifier).stop();
      await engine.unload();
      _ref.read(practiceControllerProvider.notifier).persist();
    }
    _ref.read(libraryProvider.notifier).remove(track.id);
    _ref.read(routinesProvider.notifier).purgeTrack(track.id);
    await _ref.read(audioStorageProvider).delete(track.fileName);
  }

  // ── Practice sheets ───────────────────────────────────────────────────────

  Future<void> shareSheet(Track track) {
    final sheet = PracticeSheet.fromTrack(track);
    return _ref.read(fileServiceProvider).shareTextFile(
          fileName: '${shareFileStem(track.title)}.rehearse.json',
          content: sheet.toJsonText(),
          subject: '${track.title} – practice sheet',
        );
  }

  Future<void> shareLabels(Track track) {
    return _ref.read(fileServiceProvider).shareTextFile(
          fileName: '${shareFileStem(track.title)}_labels.txt',
          content: markersAsLabelText(track),
          mimeType: 'text/plain',
          subject: '${track.title} – labels',
        );
  }

  /// Lets the user pick a sheet. Returns null if cancelled; throws
  /// [FormatException] if the file isn't a practice sheet.
  Future<PracticeSheet?> pickSheet() async {
    final text = await _ref.read(fileServiceProvider).pickTextFile();
    if (text == null) return null;
    return PracticeSheet.parse(text);
  }

  /// Adds a sheet's loops and marker sets to [track], skipping anything that
  /// is already there (so importing the same sheet twice is harmless).
  /// Returns (loops, markers) added.
  (int, int) applySheet(Track track, PracticeSheet sheet) {
    final rebased = sheet.rebasedFor(track.durationMs);
    final merged = mergeInto(track, loops: rebased.loops, sets: rebased.sets);
    _ref.read(libraryProvider.notifier).mutate(
          track.id,
          (t) => mergeInto(t, loops: rebased.loops, sets: rebased.sets).track,
        );
    return (merged.loopsAdded, merged.markersAdded);
  }

  // ── Marker export (the portable v2 file other apps read) ────────────────

  /// Builds the export for the track's active marker set, computing (and
  /// remembering) the audio's SHA-256 the first time. Null if nothing is
  /// stamped yet.
  Future<MarkerSetExport?> buildMarkerExport(Track track) async {
    final set = track.activeSet;
    if (set == null || set.markers.isEmpty) return null;
    var hash = track.contentHash;
    if (hash == null) {
      try {
        hash = await _ref.read(audioStorageProvider).sha256Of(track.fileName);
        _ref.read(libraryProvider.notifier).setContentHash(track.id, hash);
      } catch (_) {
        hash = null; // export without it rather than fail
      }
    }
    return MarkerSetExport.fromSet(track, set, contentHash: hash);
  }

  /// Shares the timestamps as plain text. False if there is nothing to share.
  Future<bool> shareMarkerExport(Track track) async {
    final export = await buildMarkerExport(track);
    if (export == null) return false;
    await _ref.read(fileServiceProvider).shareText(
          export.toJsonText(),
          subject: '${track.exportName}${track.activeSet == null ? '' : ' (${track.activeSet!.name})'} — timestamps',
        );
    return true;
  }

  /// Saves the timestamps through a "save as" dialog. Null if there is
  /// nothing to save, false if the user cancelled.
  Future<bool?> saveMarkerExport(Track track) async {
    final export = await buildMarkerExport(track);
    if (export == null) return null;
    return _ref.read(fileServiceProvider).saveTextFile(
          fileName: MarkerSetExport.suggestedFileName(track, track.activeSet),
          content: export.toJsonText(),
        );
  }

  // ── Backup & restore of everything you've built ─────────────────────────

  Future<void> shareBackup() {
    final bundle = BackupBundle.create(
      _ref.read(libraryProvider),
      _ref.read(routinesProvider),
    );
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}';
    return _ref.read(fileServiceProvider).shareTextFile(
          fileName: 'rehearse_backup_$stamp.json',
          content: bundle.toJsonText(),
          subject: 'Rehearse backup',
        );
  }

  /// Lets the user pick a backup and merges it in. Returns null if cancelled;
  /// throws [FormatException] for a file that isn't a backup. Running it
  /// again later (after importing missing audio) only adds what's still new.
  Future<RestoreReport?> restoreBackup() async {
    final text = await _ref.read(fileServiceProvider).pickTextFile();
    if (text == null) return null;
    final bundle = BackupBundle.parse(text);
    final result = applyBackup(
      bundle,
      _ref.read(libraryProvider),
      _ref.read(routinesProvider),
    );
    if (result.report.changedAnything) {
      _ref.read(libraryProvider.notifier).replaceAll(result.tracks);
      _ref.read(routinesProvider.notifier).replaceAll(result.routines);
    }
    return result.report;
  }
}

final trackActionsProvider = Provider<TrackActions>(TrackActions.new);

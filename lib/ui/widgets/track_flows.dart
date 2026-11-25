import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/track.dart';
import '../../state/library_notifier.dart';
import '../../state/track_actions.dart';
import '../navigation.dart';
import 'dialogs.dart';

/// Multi-step actions on a track, shared by the library and practice screens.
abstract final class TrackFlows {
  static Future<void> rename(BuildContext context, WidgetRef ref, Track track) async {
    final title = await promptText(
      context,
      title: 'Rename track',
      initial: track.title,
    );
    if (title != null) ref.read(libraryProvider.notifier).rename(track.id, title);
  }

  static Future<void> shareSheet(BuildContext context, WidgetRef ref, Track track) async {
    if (track.loops.isEmpty && track.markers.isEmpty) {
      showSnack(context, 'Nothing to share yet: save a loop or add a marker first');
      return;
    }
    try {
      await ref.read(trackActionsProvider).shareSheet(track);
    } catch (_) {
      if (context.mounted) showSnack(context, 'Couldn’t open the share sheet');
    }
  }

  static Future<void> importSheet(BuildContext context, WidgetRef ref, Track track) async {
    final actions = ref.read(trackActionsProvider);
    try {
      final sheet = await actions.pickSheet();
      if (sheet == null || !context.mounted) return;
      if (!sheet.matchesDuration(track.durationMs)) {
        final ok = await confirmAction(
          context,
          title: 'Different audio?',
          message: 'This sheet was made for audio ${formatMs(sheet.durationMs)} long, '
              'but this track is ${formatMs(track.durationMs)}. '
              'Loops and markers may not line up. Import anyway?',
          confirmLabel: 'Import',
        );
        if (!ok || !context.mounted) return;
      }
      final (loops, markers) = actions.applySheet(track, sheet);
      if (!context.mounted) return;
      showSnack(
        context,
        loops == 0 && markers == 0
            ? 'Nothing new: those loops and markers are already here'
            : 'Added $loops ${loops == 1 ? 'loop' : 'loops'} and '
                '$markers ${markers == 1 ? 'marker' : 'markers'}',
      );
    } on FormatException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } catch (_) {
      if (context.mounted) showSnack(context, 'Couldn’t read that file');
    }
  }

  /// Returns true if the track was deleted.
  static Future<bool> delete(BuildContext context, WidgetRef ref, Track track) async {
    final ok = await confirmAction(
      context,
      title: 'Delete “${track.title}”?',
      message: 'The audio, its loops and markers, and any routine steps that '
          'use it will be removed. This can’t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return false;
    await ref.read(trackActionsProvider).deleteTrack(track);
    return true;
  }
}

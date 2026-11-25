import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/material.dart';
import '../../../domain/gap.dart';
import '../../../domain/loop.dart';
import '../../../state/engine_providers.dart';
import '../../../state/library_notifier.dart';
import '../../../state/practice_controller.dart';
import '../../../state/routine_controller.dart';
import '../../navigation.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/small_widgets.dart';

/// Tab 2: the passages you've saved for this track.
class SavedPanel extends ConsumerWidget {
  const SavedPanel({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(trackProvider(trackId));
    final practice = ref.watch(practiceControllerProvider);
    final s = ref.watch(engineStateProvider);
    final controller = ref.read(practiceControllerProvider.notifier);
    if (track == null) return const SizedBox.shrink();

    final loops = loopsByPosition(track);
    if (loops.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmarks_outlined,
        title: 'No saved loops yet',
        message: 'Set A and B on the Loop tab, then tap “Save loop”. '
            'Saved loops bring back their speed, pitch and repeats with one tap.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${loops.length} ${loops.length == 1 ? 'loop' : 'loops'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final started = await ref
                    .read(routineControllerProvider.notifier)
                    .startAllLoops(track);
                if (started && context.mounted) {
                  unawaited(openRoutinePlayer(context));
                }
              },
              icon: const Icon(Icons.playlist_play),
              label: const Text('Play all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final loop in loops)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LoopTile(
              loop: loop,
              active: loop.id == practice.activeLoopId,
              playing: loop.id == practice.activeLoopId && s.playing,
              canOverwrite: s.hasLoop,
              onTap: () => unawaited(controller.applyLoop(loop)),
              onRename: () async {
                final name = await promptText(
                  context,
                  title: 'Rename loop',
                  initial: loop.name,
                );
                if (name != null) controller.renameLoop(loop.id, name);
              },
              onOverwrite: () {
                if (loop.id != practice.activeLoopId) {
                  unawaited(controller.applyLoop(loop));
                }
                controller.updateActiveLoop();
                showSnack(context, 'Updated “${loop.name}”');
              },
              onDelete: () async {
                final used = controller.routinesUsing(loop.id);
                if (used > 0) {
                  final ok = await confirmAction(
                    context,
                    title: 'Delete “${loop.name}”?',
                    message: 'It is used in $used ${used == 1 ? 'routine' : 'routines'}. '
                        'Those steps will be removed too.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (!ok) return;
                }
                controller.deleteLoop(loop.id);
                if (context.mounted && used == 0) {
                  showSnack(
                    context,
                    'Deleted “${loop.name}”',
                    actionLabel: 'Undo',
                    onAction: () => controller.restoreLoop(loop),
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

class _LoopTile extends StatelessWidget {
  const _LoopTile({
    required this.loop,
    required this.active,
    required this.playing,
    required this.canOverwrite,
    required this.onTap,
    required this.onRename,
    required this.onOverwrite,
    required this.onDelete,
  });

  final Loop loop;
  final bool active;
  final bool playing;
  final bool canOverwrite;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onOverwrite;
  final VoidCallback onDelete;

  String get _details {
    final parts = <String>[
      '${formatMs(loop.startMs)} – ${formatMs(loop.endMs)}',
      formatSpeed(loop.speed),
      if (loop.pitch != 0) formatPitch(loop.pitch),
      loop.repeats == 0 ? '∞' : '${loop.repeats}×',
      if (loop.gap.kind == GapKind.clip) 'your turn',
      if (loop.gap.kind == GapKind.fixed) 'wait ${formatSeconds(loop.gap.ms)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: active ? scheme.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          playing ? Icons.graphic_eq : Icons.loop,
          color: active ? scheme.onSecondaryContainer : scheme.primary,
        ),
        title: Text(loop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_details),
        trailing: PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
              case 'overwrite':
                onOverwrite();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            if (canOverwrite)
              const PopupMenuItem(
                value: 'overwrite',
                child: Text('Overwrite with current loop'),
              ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

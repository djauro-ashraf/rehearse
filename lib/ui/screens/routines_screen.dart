import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/ids.dart';
import '../../core/material.dart';
import '../../domain/routine.dart';
import '../../engine/routine_runner.dart';
import '../../state/library_notifier.dart';
import '../../state/routine_controller.dart';
import '../../state/routines_notifier.dart';
import '../navigation.dart';
import '../widgets/dialogs.dart';
import '../widgets/small_widgets.dart';
import 'routine_editor_screen.dart';
import 'settings_screen.dart';

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final routine = Routine(
      id: newId(),
      name: 'New routine',
      createdAtMs: now,
      updatedAtMs: now,
    );
    ref.read(routinesProvider.notifier).upsert(routine);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutineEditorScreen(routineId: routine.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    final tracks = ref.watch(libraryProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_create(context, ref)),
        icon: const Icon(Icons.add),
        label: const Text('New routine'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Routines'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          if (routines.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.playlist_play,
                title: 'Practise hands-free',
                message: 'A routine plays your saved loops one after another, '
                    'each repeated as many times as you choose. Build one for '
                    'your warm-up, your lesson, or this week’s verses.',
              ),
            )
          else ...[
            SliverList.builder(
              itemCount: routines.length,
              itemBuilder: (context, index) {
                final routine = routines[index];
                final resolved = resolveRoutine(routine, tracks);
                final total = resolved.steps.fold<int>(0, (sum, s) => sum + s.estimatedMs) *
                    (routine.rounds == 0 ? 1 : routine.rounds);
                final parts = <String>[
                  '${routine.steps.length} ${routine.steps.length == 1 ? 'step' : 'steps'}',
                  if (resolved.steps.isNotEmpty)
                    '${routine.rounds == 0 ? '' : '~'}${formatSeconds(total)}'
                        '${routine.rounds == 0 ? ' per round' : ''}',
                  if (routine.rounds != 1)
                    routine.rounds == 0 ? 'repeats' : '${routine.rounds} rounds',
                  if (routine.shuffle) 'shuffled',
                ];
                return ListTile(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RoutineEditorScreen(routineId: routine.id),
                    ),
                  ),
                  title: Text(routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(parts.join(' · ')),
                  leading: IconButton.filledTonal(
                    tooltip: 'Start',
                    onPressed: resolved.steps.isEmpty
                        ? null
                        : () async {
                            final started = await ref
                                .read(routineControllerProvider.notifier)
                                .start(routine);
                            if (started && context.mounted) {
                              unawaited(openRoutinePlayer(context));
                            }
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (resolved.missing > 0)
                        Tooltip(
                          message: '${resolved.missing} missing '
                              '${resolved.missing == 1 ? 'step' : 'steps'}',
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (value) async {
                          final notifier = ref.read(routinesProvider.notifier);
                          switch (value) {
                            case 'duplicate':
                              notifier.duplicate(routine.id);
                            case 'delete':
                              final ok = await confirmAction(
                                context,
                                title: 'Delete “${routine.name}”?',
                                message: 'Your loops are not affected.',
                                confirmLabel: 'Delete',
                                destructive: true,
                              );
                              if (ok) notifier.remove(routine.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ],
      ),
    );
  }
}

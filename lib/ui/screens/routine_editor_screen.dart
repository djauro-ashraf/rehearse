import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/loop_rules.dart';
import '../../domain/routine.dart';
import '../../domain/track.dart';
import '../../engine/routine_runner.dart';
import '../../state/library_notifier.dart';
import '../../state/routine_controller.dart';
import '../../state/routines_notifier.dart';
import '../navigation.dart';
import '../widgets/loop_picker_sheet.dart';
import '../widgets/step_options_sheet.dart';
import '../widgets/small_widgets.dart';

/// Edits a routine in place: every change is saved immediately, and an empty
/// routine is dropped when you leave.
class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({super.key, required this.routineId});

  final String routineId;

  @override
  ConsumerState<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  late final TextEditingController _name;
  late final RoutinesNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(routinesProvider.notifier);
    _name = TextEditingController(text: _notifier.byId(widget.routineId)?.name);
  }

  @override
  void dispose() {
    // A routine you never added a step to isn't worth keeping.
    final routine = _notifier.byId(widget.routineId);
    if (routine != null && routine.steps.isEmpty) {
      // Defer: providers can't be modified while the tree is being torn down.
      Future<void>.microtask(() => _notifier.remove(widget.routineId));
    }
    _name.dispose();
    super.dispose();
  }

  Routine? get _routine => ref.read(routinesProvider.notifier).byId(widget.routineId);

  void _update(Routine Function(Routine r) change) {
    final routine = _routine;
    if (routine != null) _notifier.upsert(change(routine));
  }

  Future<void> _addSteps() async {
    final steps = await showLoopPicker(context);
    if (steps == null || steps.isEmpty) return;
    _update((r) => r.copyWith(steps: [...r.steps, ...steps]));
  }

  Future<void> _start(Routine routine) async {
    final started = await ref.read(routineControllerProvider.notifier).start(routine);
    if (started && mounted) unawaited(openRoutinePlayer(context));
  }

  @override
  Widget build(BuildContext context) {
    final routine = ref.watch(routinesProvider.select(
      (list) => list.where((r) => r.id == widget.routineId).firstOrNull,
    ));
    final tracks = ref.watch(libraryProvider);
    if (routine == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final theme = Theme.of(context);
    final byId = {for (final t in tracks) t.id: t};
    final canStart = resolveRoutine(routine, tracks).steps.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Routine')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canStart ? () => unawaited(_start(routine)) : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (value) {
              final clean = value.trim();
              if (clean.isNotEmpty) _update((r) => r.copyWith(name: clean));
            },
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Play',
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Rounds')),
                    StepperField(
                      display: routine.rounds == 0 ? '∞' : '${routine.rounds}',
                      minusEnabled: routine.rounds > 0,
                      plusEnabled: routine.rounds < 99,
                      onMinus: () =>
                          _update((r) => r.copyWith(rounds: r.rounds - 1)),
                      onPlus: () =>
                          _update((r) => r.copyWith(rounds: r.rounds + 1)),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shuffle steps'),
                  subtitle: const Text('A new random order every round'),
                  value: routine.shuffle,
                  onChanged: (v) => _update((r) => r.copyWith(shuffle: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  routine.steps.isEmpty ? 'Steps' : 'Steps · hold ≡ to reorder',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addSteps,
                icon: const Icon(Icons.add),
                label: const Text('Add loops'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (routine.steps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: EmptyState(
                icon: Icons.queue_music,
                title: 'No steps yet',
                message: 'Add saved loops (or whole tracks) and choose how many '
                    'times each one repeats.',
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: routine.steps.length,
              onReorderItem: (oldIndex, newIndex) {
                _update((r) {
                  final steps = [...r.steps];
                  steps.insert(newIndex, steps.removeAt(oldIndex));
                  return r.copyWith(steps: steps);
                });
              },
              itemBuilder: (context, index) {
                final step = routine.steps[index];
                final track = byId[step.trackId];
                final loop = track?.loopById(step.loopId);
                final missing = track == null || (step.loopId != null && loop == null);
                final others = [
                  for (var i = 0; i < routine.steps.length; i++)
                    if (routine.steps[i].id != step.id)
                      (
                        id: routine.steps[i].id,
                        label: 'Step ${i + 1} · ${_label(routine.steps[i], byId)}',
                      ),
                ];
                final next = step.next;
                final targetIndex = routine.steps.indexWhere((s) => s.id == next.stepId);
                final summary = <String>[
                  step.repeats == 0 ? '∞' : '${step.repeats}×',
                  if (step.pauseAfterMs > 0) 'pause ${formatSeconds(step.pauseAfterMs)}',
                  switch (next.kind) {
                    StepNextKind.next => '',
                    StepNextKind.stop => 'then stop',
                    StepNextKind.shuffle => 'then a random step',
                    StepNextKind.goTo => targetIndex < 0
                        ? 'then next step'
                        : 'then step ${targetIndex + 1}',
                  },
                ].where((p) => p.isNotEmpty).join(' · ');
                return Padding(
                  key: ValueKey(step.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StepCard(
                    index: index,
                    title: missing ? 'Missing' : (loop?.name ?? 'Whole track'),
                    subtitle: missing
                        ? 'This loop or track was deleted'
                        : '${track.title} · '
                            '${loop == null ? formatMs(track.durationMs) : '${formatMs(loop.startMs)}–${formatMs(loop.endMs)}'}'
                            '${loop == null ? '' : ' · ${formatSpeed(loop.speed)}'}',
                    summary: summary,
                    missing: missing,
                    repeats: step.repeats,
                    onRepeats: (value) => _update((r) => r.copyWith(steps: [
                          for (final s in r.steps)
                            s.id == step.id ? s.copyWith(repeats: value) : s,
                        ])),
                    onOptions: () async {
                      final edited = await showStepOptions(context, step: step, others: others);
                      if (edited == null) return;
                      _update((r) => r.copyWith(steps: [
                            for (final s in r.steps) s.id == step.id ? edited : s,
                          ]));
                    },
                    onDelete: () => _update((r) => r.copyWith(steps: [
                          for (final s in r.steps)
                            if (s.id != step.id) s,
                        ])),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  static String _label(RoutineStep step, Map<String, Track> byId) {
    final track = byId[step.trackId];
    final loop = track?.loopById(step.loopId);
    if (track == null) return 'Missing';
    return loop?.name ?? 'Whole track (${track.title})';
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.missing,
    required this.repeats,
    required this.onRepeats,
    required this.onOptions,
    required this.onDelete,
  });

  final int index;
  final String title;
  final String subtitle;
  final String summary;
  final bool missing;
  final int repeats;
  final void Function(int value) onRepeats;
  final VoidCallback onOptions;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: missing ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Column(
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove step',
                  onPressed: onDelete,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (!missing)
              Padding(
                padding: const EdgeInsets.only(left: 52, right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onOptions,
                        icon: const Icon(Icons.tune, size: 18),
                        label: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                      ),
                    ),
                    StepperField(
                      display: repeats == 0 ? '∞' : '$repeats×',
                      valueWidth: 48,
                      minusEnabled: repeats > 0,
                      plusEnabled: repeats < LoopRules.maxRepeats,
                      onMinus: () => onRepeats(repeats - 1),
                      onPlus: () => onRepeats(repeats + 1),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

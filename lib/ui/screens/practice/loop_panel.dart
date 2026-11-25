import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/material.dart';
import '../../../domain/gap.dart';
import '../../../domain/loop.dart';
import '../../../domain/loop_rules.dart';
import '../../../engine/engine_state.dart';
import '../../../state/engine_providers.dart';
import '../../../state/library_notifier.dart';
import '../../../state/practice_controller.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/repeat_sheet.dart';
import '../../widgets/small_widgets.dart';

/// Tab 1: set A and B, choose speed and pitch, save the loop.
class LoopPanel extends ConsumerWidget {
  const LoopPanel({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineStateProvider);
    final practice = ref.watch(practiceControllerProvider);
    final track = ref.watch(trackProvider(trackId));
    final controller = ref.read(practiceControllerProvider.notifier);
    final activeLoop = track?.loopById(practice.activeLoopId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SectionCard(
          title: 'A–B loop',
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PointBox(
                      label: 'A',
                      ms: s.loopStartMs,
                      enabled: !practice.locked,
                      onSet: controller.setA,
                      onNudge: controller.nudgeA,
                      onEdit: () async {
                        final ms = await promptTime(
                          context,
                          title: 'Set A',
                          initialMs: s.loopStartMs ?? 0,
                          maxMs: s.durationMs,
                        );
                        if (ms != null) controller.setAExact(ms);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PointBox(
                      label: 'B',
                      ms: s.loopEndMs,
                      enabled: !practice.locked,
                      onSet: controller.setB,
                      onNudge: controller.nudgeB,
                      onEdit: () async {
                        final ms = await promptTime(
                          context,
                          title: 'Set B',
                          initialMs: s.loopEndMs ?? 0,
                          maxMs: s.durationMs,
                        );
                        if (ms != null) controller.setBExact(ms);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Loop'),
                subtitle: Text(_loopSummary(s)),
                value: s.loopOn,
                onChanged: (_) => unawaited(controller.toggleLoop()),
                secondary: s.hasLoop && !practice.locked
                    ? IconButton(
                        tooltip: 'Clear A–B',
                        onPressed: controller.clearLoop,
                        icon: const Icon(Icons.close),
                      )
                    : null,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.repeat, size: 18),
                      label: Text(s.repeats == 0 ? 'Repeat ∞' : 'Repeat ${s.repeats}×'),
                      onPressed: () => unawaited(showRepeatSheet(context)),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.record_voice_over_outlined, size: 18),
                      label: Text(_gapLabel(s.gap)),
                      onPressed: () => unawaited(showRepeatSheet(context)),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.trending_up, size: 18),
                      label: Text(
                        s.trainer != null && s.trainer!.enabled
                            ? 'Trainer ${formatSpeed(s.trainer!.start)} → ${formatSpeed(s.trainer!.target)}'
                            : 'Speed trainer',
                      ),
                      onPressed: () => unawaited(showRepeatSheet(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Speed',
          trailing: s.speed == 1.0
              ? null
              : TextButton(
                  onPressed: () => unawaited(controller.setSpeed(1.0)),
                  child: const Text('Reset'),
                ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HoldIconButton(
                    icon: Icons.remove,
                    tooltip: 'Slower',
                    enabled: s.speed > LoopRules.minSpeed,
                    onStep: (m) => unawaited(controller.nudgeSpeed(-m)),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      formatSpeed(s.speed),
                      textAlign: TextAlign.center,
                      style: tabular(Theme.of(context).textTheme.headlineMedium),
                    ),
                  ),
                  HoldIconButton(
                    icon: Icons.add,
                    tooltip: 'Faster',
                    enabled: s.speed < LoopRules.maxSpeed,
                    onStep: (m) => unawaited(controller.nudgeSpeed(m)),
                  ),
                ],
              ),
              Slider(
                value: s.speed.clamp(LoopRules.minSpeed, LoopRules.maxSpeed),
                min: LoopRules.minSpeed,
                max: LoopRules.maxSpeed,
                divisions: 55,
                label: formatSpeed(s.speed),
                onChanged: (v) => unawaited(controller.setSpeed(v)),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    ChoiceChip(
                      label: Text(formatSpeed(preset)),
                      selected: (s.speed - preset).abs() < 0.001,
                      onSelected: (_) => unawaited(controller.setSpeed(preset)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Pitch',
          trailing: s.pitch == 0
              ? null
              : TextButton(
                  onPressed: () => unawaited(controller.setPitch(0)),
                  child: const Text('Reset'),
                ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Lower pitch',
                    onPressed: s.pitch > LoopRules.minPitch
                        ? () => unawaited(controller.setPitch(s.pitch - 1))
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      formatPitch(s.pitch),
                      textAlign: TextAlign.center,
                      style: tabular(Theme.of(context).textTheme.headlineMedium),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Raise pitch',
                    onPressed: s.pitch < LoopRules.maxPitch
                        ? () => unawaited(controller.setPitch(s.pitch + 1))
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Slider(
                value: s.pitch,
                min: LoopRules.minPitch,
                max: LoopRules.maxPitch,
                divisions: 24,
                label: formatPitch(s.pitch),
                onChanged: (v) => unawaited(controller.setPitch(v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SaveBar(activeLoop: activeLoop, state: s),
      ],
    );
  }

  static String _loopSummary(EngineState s) {
    if (!s.hasLoop) return 'Set A and B, or just turn on to loop 10 s from here';
    if (s.targetReached) {
      return 'Done · ${s.pass} ${s.pass == 1 ? 'pass' : 'passes'}. Press play to go again';
    }
    if (s.repeats == 0) {
      return s.pass == 0 ? 'Repeats until you stop' : 'Pass ${s.pass} · repeats until you stop';
    }
    return 'Pass ${math.min(s.pass + 1, s.repeats)} of ${s.repeats}';
  }

  static String _gapLabel(Gap gap) => switch (gap.kind) {
        GapKind.none => 'No gap',
        GapKind.fixed => 'Wait ${formatSeconds(gap.ms)}',
        GapKind.clip => 'Your turn',
      };
}

class _PointBox extends StatelessWidget {
  const _PointBox({
    required this.label,
    required this.ms,
    required this.enabled,
    required this.onSet,
    required this.onNudge,
    required this.onEdit,
  });

  final String label;
  final int? ms;
  final bool enabled;
  final VoidCallback onSet;
  final void Function(int deltaMs) onNudge;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PracticeColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colors.loop, shape: BoxShape.circle),
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.surface,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? onEdit : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                ms == null ? '—' : formatMs(ms!, tenths: true),
                style: tabular(theme.textTheme.titleLarge),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              HoldIconButton(
                icon: Icons.remove,
                tooltip: 'Nudge $label earlier',
                enabled: enabled && ms != null,
                size: 36,
                onStep: (m) => onNudge(-100 * m),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.tonal(
                    onPressed: enabled ? onSet : null,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Set here'),
                  ),
                ),
              ),
              HoldIconButton(
                icon: Icons.add,
                tooltip: 'Nudge $label later',
                enabled: enabled && ms != null,
                size: 36,
                onStep: (m) => onNudge(100 * m),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends ConsumerWidget {
  const _SaveBar({required this.activeLoop, required this.state});

  final Loop? activeLoop;
  final EngineState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(practiceControllerProvider.notifier);
    final loop = activeLoop;

    Future<void> save() async {
      final saved = controller.saveLoop();
      if (saved == null || !context.mounted) return;
      showSnack(
        context,
        'Saved “${saved.name}”',
        actionLabel: 'Rename',
        onAction: () async {
          final name = await promptText(
            context,
            title: 'Rename loop',
            initial: saved.name,
          );
          if (name != null) controller.renameLoop(saved.id, name);
        },
      );
    }

    if (loop == null) {
      return FilledButton.icon(
        onPressed: state.hasLoop ? save : null,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Save loop'),
      );
    }

    final modified = loopIsModified(loop, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            modified ? 'Changed from “${loop.name}”' : 'Playing “${loop.name}”',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: modified
                    ? () {
                        controller.updateActiveLoop();
                        showSnack(context, 'Updated “${loop.name}”');
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Update'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: state.hasLoop ? save : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save as new'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

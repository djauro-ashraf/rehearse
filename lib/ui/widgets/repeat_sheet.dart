import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/gap.dart';
import '../../domain/loop_rules.dart';
import '../../domain/speed_trainer.dart';
import '../../state/engine_providers.dart';
import '../../state/practice_controller.dart';
import '../../state/settings_notifier.dart';
import 'small_widgets.dart';

Future<void> showRepeatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _RepeatSheet(),
  );
}

/// Everything about how a loop repeats: how many times, what happens between
/// passes, and whether the speed ramps up.
class _RepeatSheet extends ConsumerWidget {
  const _RepeatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineStateProvider);
    final controller = ref.read(practiceControllerProvider.notifier);
    final theme = Theme.of(context);
    final trainer = s.trainer ?? ref.watch(settingsProvider).trainer;
    final trainerOn = s.trainer != null && s.trainer!.enabled;

    void editTrainer(SpeedTrainer Function(SpeedTrainer t) change) {
      unawaited(controller.setTrainer(change(trainer).copyWith(enabled: true)));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repeat & timing', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            _Row(
              title: 'Repeats',
              caption: s.repeats == 0
                  ? 'Plays until you stop it.'
                  : 'Stops after ${s.repeats} ${s.repeats == 1 ? 'pass' : 'passes'}.',
              child: StepperField(
                display: s.repeats == 0 ? '∞' : '${s.repeats}',
                minusEnabled: s.repeats > 0,
                plusEnabled: s.repeats < LoopRules.maxRepeats,
                onMinus: () => controller.setRepeats(s.repeats - 1),
                onPlus: () => controller.setRepeats(s.repeats + 1),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final n in const [0, 3, 5, 10, 20, 50, 100])
                  ChoiceChip(
                    label: Text(n == 0 ? '∞' : '$n×'),
                    selected: s.repeats == n,
                    onSelected: (_) => controller.setRepeats(n),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('After each pass', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            SegmentedButton<GapKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: GapKind.none, label: Text('Straight on')),
                ButtonSegment(value: GapKind.fixed, label: Text('Wait')),
                ButtonSegment(value: GapKind.clip, label: Text('Your turn')),
              ],
              selected: {s.gap.kind},
              onSelectionChanged: (selection) {
                controller.setGap(switch (selection.first) {
                  GapKind.none => const Gap.none(),
                  GapKind.fixed => Gap.fixed(s.gap.ms > 0 ? s.gap.ms : 2000),
                  GapKind.clip => const Gap.clip(),
                });
              },
            ),
            const SizedBox(height: 8),
            switch (s.gap.kind) {
              GapKind.none => const _Caption('Jump straight back to A.'),
              GapKind.fixed => _Row(
                  title: 'Wait',
                  caption: 'Silence between passes.',
                  child: StepperField(
                    display: formatSeconds(s.gap.ms),
                    minusEnabled: s.gap.ms > 500,
                    plusEnabled: s.gap.ms < LoopRules.maxGapMs,
                    onMinus: () => controller.setGap(Gap.fixed(s.gap.ms - 500)),
                    onPlus: () => controller.setGap(Gap.fixed(s.gap.ms + 500)),
                  ),
                ),
              GapKind.clip => const _Caption(
                  'Pauses for as long as the loop lasts, so you can repeat '
                  'it out loud before it plays again.',
                ),
            },
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Speed trainer'),
              subtitle: const Text('Start slow and speed up as you repeat.'),
              value: trainerOn,
              onChanged: (on) =>
                  controller.setTrainer(trainer.copyWith(enabled: on)),
            ),
            if (trainerOn) ...[
              _Row(
                title: 'Start at',
                child: StepperField(
                  display: formatSpeed(trainer.start),
                  minusEnabled: trainer.start > LoopRules.minSpeed,
                  plusEnabled: trainer.start < trainer.target,
                  onMinus: () => editTrainer((t) => t.copyWith(
                      start: LoopRules.clampSpeed(t.start - 0.05))),
                  onPlus: () => editTrainer((t) => t.copyWith(
                      start: LoopRules.clampSpeed(t.start + 0.05))),
                ),
              ),
              _Row(
                title: 'Up to',
                child: StepperField(
                  display: formatSpeed(trainer.target),
                  minusEnabled: trainer.target > trainer.start,
                  plusEnabled: trainer.target < LoopRules.maxSpeed,
                  onMinus: () => editTrainer((t) => t.copyWith(
                      target: LoopRules.clampSpeed(t.target - 0.05))),
                  onPlus: () => editTrainer((t) => t.copyWith(
                      target: LoopRules.clampSpeed(t.target + 0.05))),
                ),
              ),
              _Row(
                title: 'Speed up by',
                child: StepperField(
                  display: '${(trainer.step * 100).round()} %',
                  minusEnabled: trainer.step > 0.05,
                  plusEnabled: trainer.step < 0.5,
                  onMinus: () => editTrainer((t) => t.copyWith(
                      step: (t.step - 0.05).clamp(0.05, 0.5))),
                  onPlus: () => editTrainer((t) => t.copyWith(
                      step: (t.step + 0.05).clamp(0.05, 0.5))),
                ),
              ),
              _Row(
                title: 'Every',
                child: StepperField(
                  display: '${trainer.everyPasses} ${trainer.everyPasses == 1 ? 'pass' : 'passes'}',
                  valueWidth: 88,
                  minusEnabled: trainer.everyPasses > 1,
                  plusEnabled: trainer.everyPasses < 20,
                  onMinus: () => editTrainer(
                      (t) => t.copyWith(everyPasses: t.everyPasses - 1)),
                  onPlus: () => editTrainer(
                      (t) => t.copyWith(everyPasses: t.everyPasses + 1)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.child, this.caption});

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                if (caption != null)
                  Text(
                    caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

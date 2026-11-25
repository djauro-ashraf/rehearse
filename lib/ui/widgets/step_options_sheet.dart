import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/loop_rules.dart';
import '../../domain/routine.dart';
import 'small_widgets.dart';

/// A step in the routine as the options sheet needs to describe it.
typedef StepChoice = ({String id, String label});

/// Edits one routine step: how many repeats, a pause afterwards, and what
/// happens next. Returns the edited step, or null if dismissed.
Future<RoutineStep?> showStepOptions(
  BuildContext context, {
  required RoutineStep step,
  required List<StepChoice> others,
}) {
  return showModalBottomSheet<RoutineStep>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StepOptions(step: step, others: others),
  );
}

class _StepOptions extends StatefulWidget {
  const _StepOptions({required this.step, required this.others});

  final RoutineStep step;
  final List<StepChoice> others;

  @override
  State<_StepOptions> createState() => _StepOptionsState();
}

class _StepOptionsState extends State<_StepOptions> {
  late RoutineStep _step = widget.step;

  void _set(RoutineStep step) => setState(() => _step = step);

  int _pauseStep(int ms, {required bool up}) {
    final unit = ms < 10000 ? 1000 : (ms < 60000 ? 5000 : 30000);
    final next = up ? ms + unit : ms - (ms <= unit ? ms : unit);
    return next.clamp(0, LoopRules.maxStepPauseMs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _step.next;
    final target = widget.others.any((o) => o.id == next.stepId) ? next.stepId : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Step options', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('Repeats')),
                StepperField(
                  display: _step.repeats == 0 ? '∞' : '${_step.repeats}',
                  minusEnabled: _step.repeats > 0,
                  plusEnabled: _step.repeats < LoopRules.maxRepeats,
                  onMinus: () => _set(_step.copyWith(repeats: _step.repeats - 1)),
                  onPlus: () => _set(_step.copyWith(repeats: _step.repeats + 1)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final n in const [0, 1, 3, 5, 10, 20, 50, 100])
                  ChoiceChip(
                    label: Text(n == 0 ? '∞' : '$n×'),
                    selected: _step.repeats == n,
                    onSelected: (_) => _set(_step.copyWith(repeats: n)),
                  ),
              ],
            ),
            if (_step.repeats == 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Plays until you tap Next.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const Divider(height: 32),
            Row(
              children: [
                const Expanded(child: Text('Pause after the last repeat')),
                StepperField(
                  display: _step.pauseAfterMs == 0 ? 'None' : formatSeconds(_step.pauseAfterMs),
                  valueWidth: 80,
                  minusEnabled: _step.pauseAfterMs > 0,
                  plusEnabled: _step.pauseAfterMs < LoopRules.maxStepPauseMs,
                  onMinus: () => _set(_step.copyWith(
                      pauseAfterMs: _pauseStep(_step.pauseAfterMs, up: false))),
                  onPlus: () => _set(_step.copyWith(
                      pauseAfterMs: _pauseStep(_step.pauseAfterMs, up: true))),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final ms in const [0, 3000, 5000, 10000, 30000, 60000])
                  ChoiceChip(
                    label: Text(ms == 0 ? 'None' : formatSeconds(ms)),
                    selected: _step.pauseAfterMs == ms,
                    onSelected: (_) => _set(_step.copyWith(pauseAfterMs: ms)),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Then', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Next step'),
                  selected: next.kind == StepNextKind.next,
                  onSelected: (_) => _set(_step.copyWith(next: const StepNext.next())),
                ),
                ChoiceChip(
                  label: const Text('Stop'),
                  selected: next.kind == StepNextKind.stop,
                  onSelected: (_) => _set(_step.copyWith(next: const StepNext.stop())),
                ),
                ChoiceChip(
                  label: const Text('Random step'),
                  selected: next.kind == StepNextKind.shuffle,
                  onSelected: (_) => _set(_step.copyWith(next: const StepNext.shuffle())),
                ),
                ChoiceChip(
                  label: const Text('Go to…'),
                  selected: next.kind == StepNextKind.goTo,
                  onSelected: widget.others.isEmpty
                      ? null
                      : (_) => _set(_step.copyWith(
                            next: StepNext.goTo(target ?? widget.others.first.id),
                          )),
                ),
              ],
            ),
            if (next.kind == StepNextKind.goTo && widget.others.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: target ?? widget.others.first.id,
                decoration: const InputDecoration(labelText: 'Go to step'),
                items: [
                  for (final o in widget.others)
                    DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  if (id != null) _set(_step.copyWith(next: StepNext.goTo(id)));
                },
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_step),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

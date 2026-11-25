import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../engine/routine_runner.dart';
import '../../state/app_providers.dart';
import '../../state/engine_providers.dart';
import '../../state/routine_controller.dart';
import '../theme.dart';
import '../widgets/small_widgets.dart';

/// Hands-free playback of a routine: what's playing now, what's next, and
/// big controls.
class RoutinePlayerScreen extends ConsumerWidget {
  const RoutinePlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(routineControllerProvider);
    final s = ref.watch(engineStateProvider);
    final controller = ref.read(routineControllerProvider.notifier);
    final runner = session.runner;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = PracticeColors.of(context);

    if (runner.status == RunnerStatus.idle) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.playlist_play,
          title: 'Nothing is playing',
          message: 'Start a routine from the Routines tab.',
        ),
      );
    }

    final finished = runner.status == RunnerStatus.finished;
    final step = runner.current;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Stop routine',
            onPressed: () async {
              await controller.stop();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: finished ? scheme.tertiaryContainer : scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: finished
                  ? Column(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 48, color: scheme.onTertiaryContainer),
                        const SizedBox(height: 8),
                        Text(
                          'Routine complete',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step ${runner.index + 1} of ${runner.steps.length}'
                          '${runner.rounds == 1 ? '' : ' · round ${runner.round}${runner.rounds == 0 ? '' : ' of ${runner.rounds}'}'}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step?.label ?? '',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          step == null
                              ? ''
                              : '${step.track.title} · ${formatMs(step.startMs)}–${formatMs(step.endMs)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(label: Text(formatSpeed(s.speed))),
                            if (s.pitch != 0) Chip(label: Text(formatPitch(s.pitch))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (s.holding)
                          Text(
                            'Next step in ${formatSeconds(s.gapMs)}…',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (s.inGap)
                          Text(
                            'Your turn…',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.loop,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          Text(
                            s.repeats == 0
                                ? 'Pass ${s.pass + 1} · until you tap Next'
                                : 'Pass ${math.min(s.pass + 1, s.repeats)} of ${s.repeats}',
                            style: tabular(theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            )),
                          ),
                        const SizedBox(height: 8),
                        if (s.holding)
                          TweenAnimationBuilder<double>(
                            key: ValueKey<int>(runner.index * 1000 + runner.round),
                            tween: Tween(begin: 0, end: 1),
                            duration: Duration(milliseconds: s.gapMs),
                            builder: (context, value, _) => LinearProgressIndicator(
                              value: value,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )
                        else
                          LinearProgressIndicator(
                            value: s.repeats == 0 ? null : s.pass / s.repeats,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Previous step',
                iconSize: 40,
                onPressed: finished ? null : () => unawaited(controller.previous()),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              SizedBox(
                width: 80,
                height: 80,
                child: IconButton.filled(
                  tooltip: s.playing ? 'Pause' : 'Play',
                  iconSize: 48,
                  onPressed: finished
                      ? null
                      : () => unawaited(ref.read(engineProvider).toggle()),
                  icon: Icon(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
              ),
              IconButton(
                tooltip: 'Next step',
                iconSize: 40,
                onPressed: finished ? null : () => unawaited(controller.next()),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Steps', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < runner.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Card(
                color: !finished && i == runner.index ? scheme.secondaryContainer : null,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: finished ? null : () => unawaited(controller.goTo(i)),
                  leading: Icon(
                    finished || i < runner.index
                        ? Icons.check_circle_outline
                        : i == runner.index
                            ? Icons.graphic_eq
                            : Icons.radio_button_unchecked,
                  ),
                  title: Text(runner.steps[i].label),
                  subtitle: Text(
                    '${runner.steps[i].track.title} · '
                    '${runner.steps[i].step.repeats == 0 ? '∞' : '${runner.steps[i].step.repeats}×'}',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

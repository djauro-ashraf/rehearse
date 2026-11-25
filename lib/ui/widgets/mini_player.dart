import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../state/app_providers.dart';
import '../../state/engine_providers.dart';
import '../../state/routine_controller.dart';
import '../navigation.dart';
import 'position_builder.dart';

/// The "now playing" strip above the navigation bar. Tap it to get back to
/// the player.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineStateProvider);
    final session = ref.watch(routineControllerProvider);
    if (!s.hasTrack) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final runner = session.runner;
    final inRoutine = runner.isActive;

    final title = inRoutine ? session.name : s.title;
    final subtitle = inRoutine
        ? 'Step ${runner.index + 1} of ${runner.steps.length}'
            '${runner.current == null ? '' : ' · ${runner.current!.label}'}'
        : s.loopOn && s.hasLoop
            ? 'Looping ${formatMs(s.loopStartMs!)}–${formatMs(s.loopEndMs!)}'
                '${s.pass > 0 ? ' · pass ${s.pass}' : ''}'
            : formatSpeed(s.speed);

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () {
          if (inRoutine) {
            unawaited(openRoutinePlayer(context));
          } else {
            unawaited(openPractice(context, s.trackId!));
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PositionBuilder(
              builder: (context, position) => LinearProgressIndicator(
                value: s.durationMs <= 0
                    ? 0
                    : (position / s.durationMs).clamp(0.0, 1.0),
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
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
                          s.inGap ? 'Your turn…' : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.playing ? 'Pause' : 'Play',
                    onPressed: s.loading
                        ? null
                        : () => unawaited(ref.read(engineProvider).toggle()),
                    icon: Icon(
                      s.playing
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 38,
                    ),
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

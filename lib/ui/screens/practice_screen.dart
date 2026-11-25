import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/marker.dart';
import '../../engine/engine_state.dart';
import '../../state/engine_providers.dart';
import '../../state/library_notifier.dart';
import '../../state/practice_controller.dart';
import '../../state/settings_notifier.dart';
import '../widgets/loop_timeline.dart';
import '../widgets/position_builder.dart';
import '../widgets/small_widgets.dart';
import '../widgets/track_flows.dart';
import '../theme.dart';
import 'practice/loop_panel.dart';
import 'practice/marks_panel.dart';
import 'practice/saved_panel.dart';

/// The heart of the app: one track, its timeline, transport and drill tools.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late String _trackId = widget.trackId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref.read(practiceControllerProvider.notifier).open(_trackId),
      );
    });
  }

  /// Opens the previous/next track in this same screen.
  Future<void> _openAdjacent(int delta) async {
    final id = await ref.read(practiceControllerProvider.notifier).openAdjacent(delta);
    if (id != null && mounted) setState(() => _trackId = id);
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(trackProvider(_trackId));
    final practice = ref.watch(practiceControllerProvider);
    final s = ref.watch(engineStateProvider);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.music_off_outlined,
          title: 'Track not found',
          message: 'It may have been deleted.',
        ),
      );
    }

    final ready = practice.trackId == _trackId && s.trackId == _trackId;

    return Scaffold(
      appBar: AppBar(
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              switch (value) {
                case 'rename':
                  await TrackFlows.rename(context, ref, track);
                case 'share':
                  await TrackFlows.shareSheet(context, ref, track);
                case 'import':
                  await TrackFlows.importSheet(context, ref, track);
                case 'delete':
                  final deleted = await TrackFlows.delete(context, ref, track);
                  if (deleted && context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'share', child: Text('Share practice sheet')),
              PopupMenuItem(value: 'import', child: Text('Import practice sheet')),
              PopupMenuItem(value: 'delete', child: Text('Delete track')),
            ],
          ),
        ],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : s.error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Can’t play this file',
                  message: s.error!,
                  action: FilledButton.tonal(
                    onPressed: () async {
                      final deleted = await TrackFlows.delete(context, ref, track);
                      if (deleted && context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Remove from library'),
                  ),
                )
              : _Body(trackId: _trackId, onAdjacent: _openAdjacent),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.trackId, required this.onAdjacent});

  final String trackId;
  final Future<void> Function(int delta) onAdjacent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(trackProvider(trackId));
    if (track == null) return const SizedBox.shrink();
    final s = ref.watch(engineStateProvider);
    final practice = ref.watch(practiceControllerProvider);
    final controller = ref.read(practiceControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              children: [
                PositionBuilder(
                  builder: (context, position) => LoopTimeline(
                    durationMs: s.durationMs,
                    positionMs: position,
                    loopStartMs: s.loopStartMs,
                    loopEndMs: s.loopEndMs,
                    loopOn: s.loopOn,
                    locked: practice.locked,
                    zoomToLoop: practice.zoom,
                    markerPositions: [
                      for (final m in track.markers)
                        if (m.tier == MarkerTier.mark) m.positionMs,
                    ],
                    minimarkPositions: [
                      for (final m in track.markers)
                        if (m.tier == MarkerTier.minimark) m.positionMs,
                    ],
                    savedRegions: [for (final l in track.loops) (l.startMs, l.endMs)],
                    onSeek: (ms) => unawaited(controller.seek(ms)),
                    onRegionChanged: controller.dragRegion,
                    onRegionChangeEnd: ({required movedB}) =>
                        controller.endDrag(movedB: movedB),
                  ),
                ),
                Row(
                  children: [
                    PositionBuilder(
                      builder: (context, position) => Text(
                        '${formatMs(position, tenths: true)} / ${formatMs(s.durationMs)}',
                        style: tabular(theme.textTheme.bodyMedium),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: practice.zoom ? 'Show whole track' : 'Zoom to loop',
                      isSelected: practice.zoom,
                      onPressed: s.hasLoop ? controller.toggleZoom : null,
                      icon: const Icon(Icons.zoom_in_map),
                      selectedIcon: const Icon(Icons.zoom_out_map),
                    ),
                    IconButton(
                      tooltip: practice.locked ? 'Unlock A–B' : 'Lock A–B',
                      isSelected: practice.locked,
                      onPressed: controller.toggleLock,
                      icon: const Icon(Icons.lock_open),
                      selectedIcon: const Icon(Icons.lock),
                    ),
                  ],
                ),
                _StatusLine(state: s),
                _Transport(trackId: trackId, onAdjacent: onAdjacent),
              ],
            ),
          ),
          const SizedBox(height: 4),
          TabBar(
            tabs: [
              const Tab(text: 'Loop'),
              Tab(text: 'Saved · ${track.loops.length}'),
              Tab(text: 'Marks · ${track.activeSet?.count(MarkerTier.mark) ?? 0}'),
            ],
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: TabBarView(
              children: [
                LoopPanel(trackId: trackId),
                SavedPanel(trackId: trackId),
                MarksPanel(trackId: trackId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your turn…" countdown while a gap between passes is running.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PracticeColors.of(context);
    if (!state.inGap) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          Text(
            'Your turn…',
            style: theme.textTheme.titleSmall?.copyWith(color: colors.loop),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            key: ValueKey<int>(state.pass),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: state.gapMs),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              color: colors.loop,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({required this.trackId, required this.onAdjacent});

  final String trackId;
  final Future<void> Function(int delta) onAdjacent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineStateProvider);
    final track = ref.watch(trackProvider(trackId));
    if (track == null) return const SizedBox.shrink();
    final skip = ref.watch(skipSecondsProvider);
    final controller = ref.read(practiceControllerProvider.notifier);
    // Previous/next *track*, in natural A→Z order (like the library queue).
    final ordered = [...ref.watch(libraryProvider)]
      ..sort((a, b) => naturalCompare(a.title, b.title));
    final index = ordered.indexWhere((t) => t.id == trackId);
    final hasPrevious = index > 0;
    final hasNext = index >= 0 && index < ordered.length - 1;
    final scheme = Theme.of(context).colorScheme;

    IconData back() => switch (skip) {
          10 => Icons.replay_10,
          30 => Icons.replay_30,
          _ => Icons.replay_5,
        };
    IconData forward() => switch (skip) {
          10 => Icons.forward_10,
          30 => Icons.forward_30,
          _ => Icons.forward_5,
        };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Previous track',
          iconSize: 32,
          onPressed: hasPrevious ? () => unawaited(onAdjacent(-1)) : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          tooltip: 'Back $skip seconds',
          iconSize: 34,
          onPressed: () => unawaited(controller.skipBack()),
          icon: Icon(back()),
        ),
        SizedBox(
          width: 76,
          height: 76,
          child: s.loading
              ? const Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(),
                )
              : IconButton.filled(
                  tooltip: s.playing ? 'Pause' : 'Play',
                  iconSize: 44,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                  onPressed: () => unawaited(controller.togglePlay()),
                  icon: Icon(
                    s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
        ),
        IconButton(
          tooltip: 'Forward $skip seconds',
          iconSize: 34,
          onPressed: () => unawaited(controller.skipForward()),
          icon: Icon(forward()),
        ),
        IconButton(
          tooltip: 'Next track',
          iconSize: 32,
          onPressed: hasNext ? () => unawaited(onAdjacent(1)) : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

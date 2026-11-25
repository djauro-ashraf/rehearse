import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/material.dart';
import '../../../domain/marker.dart';
import '../../../domain/segments.dart';
import '../../../domain/track.dart';
import '../../../state/app_providers.dart';
import '../../../state/library_notifier.dart';
import '../../../state/practice_controller.dart';
import '../../../state/track_actions.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/small_widgets.dart';

String _tierName(MarkerTier tier) => tier == MarkerTier.mark ? 'Marks' : 'Minimarks';

/// Tab 3: stamp the track into Marks (verses, phrases, chapters) and
/// Minimarks (words inside one), keep several stamp sets per track, lock
/// finished work, and export the timestamps for other apps.
class MarksPanel extends ConsumerStatefulWidget {
  const MarksPanel({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<MarksPanel> createState() => _MarksPanelState();
}

class _MarksPanelState extends ConsumerState<MarksPanel> {
  String? _expandedId;

  PracticeController get _controller =>
      ref.read(practiceControllerProvider.notifier);

  /// Shows the right message for a refused edit; true if it went through.
  bool _check(MarkerOutcome outcome, MarkerTier tier) {
    switch (outcome) {
      case MarkerOutcome.done:
        return true;
      case MarkerOutcome.locked:
        showSnack(context, '${_tierName(tier)} are locked — tap the ${_tierName(tier)} chip to edit');
      case MarkerOutcome.needsMark:
        showSnack(context, 'Add a Mark before adding Minimarks here');
      case MarkerOutcome.duplicate:
        showSnack(context, 'There is already a ${tier == MarkerTier.mark ? 'mark' : 'minimark'} here');
      case MarkerOutcome.noTrack:
        break;
    }
    return false;
  }

  Future<void> _stamp(MarkerTier tier) async {
    unawaited(HapticFeedback.lightImpact());
    final result = _controller.stamp(tier);
    if (!_check(result.outcome, tier)) return;
    if (result.needsName && result.marker != null) {
      // It landed before existing stamps; don't guess a number, ask.
      final label = await promptText(
        context,
        title: 'Name this ${tier == MarkerTier.mark ? 'mark' : 'minimark'}',
        hint: 'Label',
      );
      if (label != null) _controller.renameMarker(result.marker!.id, label);
    }
  }

  Future<void> _export(Track track, {required bool save}) async {
    final actions = ref.read(trackActionsProvider);
    try {
      if (save) {
        final saved = await actions.saveMarkerExport(track);
        if (!mounted) return;
        if (saved == null) showSnack(context, 'Nothing to export yet');
        if (saved ?? false) showSnack(context, 'Saved');
      } else {
        final shared = await actions.shareMarkerExport(track);
        if (!mounted) return;
        if (!shared) showSnack(context, 'Nothing to export yet');
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Couldn’t export the timestamps');
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(trackProvider(widget.trackId));
    if (track == null) return const SizedBox.shrink();
    final set = track.activeSet;
    final segments = buildSegments(track.markers, track.durationMs);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SetBar(track: track, onExport: _export),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final tier in MarkerTier.values) ...[
              FilterChip(
                avatar: Icon(
                  (set?.isLocked(tier) ?? false) ? Icons.lock : Icons.lock_open,
                  size: 18,
                ),
                label: Text(_tierName(tier)),
                selected: set?.isLocked(tier) ?? false,
                onSelected: (_) => _controller.toggleMarkerLock(tier),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Previous segment',
              onPressed: segments.isEmpty ? null : () => unawaited(_controller.jumpSegment(-1)),
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton(
              tooltip: 'Next segment',
              onPressed: segments.isEmpty ? null : () => unawaited(_controller.jumpSegment(1)),
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => unawaited(_stamp(MarkerTier.mark)),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Mark here'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => unawaited(_stamp(MarkerTier.minimark)),
                icon: const Icon(Icons.flag_circle_outlined),
                label: const Text('Minimark here'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (segments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Tap “Mark here” each time something new begins: a verse, a '
              'phrase, a chapter. Use Minimarks for finer points inside one '
              '(like words). Then loop or play each part with one tap.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _SegmentTracker(
            segments: segments,
            builder: (context, current) => Column(
              children: [
                for (final segment in segments) ...[
                  _MarkerRow(
                    marker: segment.mark,
                    endMs: segment.endMs,
                    current: segment.index == current,
                    expanded: _expandedId == segment.mark.id,
                    onToggle: () => setState(() => _expandedId =
                        _expandedId == segment.mark.id ? null : segment.mark.id),
                    check: _check,
                  ),
                  for (var i = 0; i < segment.minimarks.length; i++)
                    _MarkerRow(
                      marker: segment.minimarks[i],
                      endMs: segment.minimarkEndMs(i),
                      depth: 1,
                      expanded: _expandedId == segment.minimarks[i].id,
                      onToggle: () => setState(() => _expandedId =
                          _expandedId == segment.minimarks[i].id
                              ? null
                              : segment.minimarks[i].id),
                      check: _check,
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The marker-set chips plus the set / export menu.
class _SetBar extends ConsumerWidget {
  const _SetBar({required this.track, required this.onExport});

  final Track track;
  final Future<void> Function(Track track, {required bool save}) onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(practiceControllerProvider.notifier);
    final active = track.activeSet;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final set in track.markerSets) ...[
                  ChoiceChip(
                    label: Text(set.name),
                    selected: set.id == active?.id,
                    onSelected: (_) => controller.selectMarkerSet(set.id),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(track.markerSets.isEmpty ? 'Set 1' : 'New set'),
                  onPressed: () async {
                    final name = await promptText(
                      context,
                      title: 'New stamp set',
                      hint: 'e.g. Reciter B',
                      confirmLabel: 'Create',
                    );
                    if (name != null) controller.createMarkerSet(name);
                  },
                ),
              ],
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Stamp set and export',
          onSelected: (value) async {
            switch (value) {
              case 'rename':
                if (active == null) return;
                final name = await promptText(context, title: 'Rename set', initial: active.name);
                if (name != null) controller.renameMarkerSet(active.id, name);
              case 'delete':
                if (active == null) return;
                final ok = await confirmAction(
                  context,
                  title: 'Delete “${active.name}”?',
                  message: 'Its ${active.markers.length} markers will be removed. '
                      'Your saved loops are not affected.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (ok) controller.deleteMarkerSet(active.id);
              case 'share':
                await onExport(track, save: false);
              case 'save':
                await onExport(track, save: true);
              case 'labels':
                try {
                  await ref.read(trackActionsProvider).shareLabels(track);
                } catch (_) {
                  if (context.mounted) showSnack(context, 'Couldn’t open the share sheet');
                }
              case 'loops':
                final n = controller.loopsFromMarkers();
                if (context.mounted) {
                  showSnack(
                    context,
                    n == 0
                        ? 'Every segment is already a saved loop'
                        : 'Saved $n ${n == 1 ? 'loop' : 'loops'} from your marks',
                  );
                }
              case 'clear':
                final ok = await confirmAction(
                  context,
                  title: 'Remove all markers?',
                  message: 'From “${active?.name ?? 'this set'}”. Locked markers stay. '
                      'Your saved loops are not affected.',
                  confirmLabel: 'Remove',
                  destructive: true,
                );
                if (ok) controller.clearMarkers();
            }
          },
          itemBuilder: (_) => [
            if (active != null) ...const [
              PopupMenuItem(value: 'rename', child: Text('Rename set')),
              PopupMenuItem(value: 'delete', child: Text('Delete set')),
              PopupMenuDivider(),
            ],
            const PopupMenuItem(value: 'share', child: Text('Share timestamps')),
            const PopupMenuItem(value: 'save', child: Text('Save timestamps to file…')),
            const PopupMenuItem(value: 'labels', child: Text('Share as label file')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'loops', child: Text('Save every segment as a loop')),
            const PopupMenuItem(value: 'clear', child: Text('Remove all markers')),
          ],
        ),
      ],
    );
  }
}

/// Tells its child which Mark segment the playhead is in, rebuilding only
/// when that changes (not 30 times a second).
class _SegmentTracker extends ConsumerStatefulWidget {
  const _SegmentTracker({required this.segments, required this.builder});

  final List<MarkSegment> segments;
  final Widget Function(BuildContext context, int current) builder;

  @override
  ConsumerState<_SegmentTracker> createState() => _SegmentTrackerState();
}

class _SegmentTrackerState extends ConsumerState<_SegmentTracker> {
  StreamSubscription<int>? _subscription;
  int _current = -1;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(engineProvider);
    _current = segmentIndexAt(widget.segments, engine.positionMs);
    _subscription = engine.positions.listen((position) {
      final index = segmentIndexAt(widget.segments, position);
      if (index != _current) setState(() => _current = index);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _current);
}

/// One Mark or Minimark: tap to jump there and reveal its tools.
class _MarkerRow extends ConsumerWidget {
  const _MarkerRow({
    required this.marker,
    required this.endMs,
    required this.expanded,
    required this.onToggle,
    required this.check,
    this.depth = 0,
    this.current = false,
  });

  final Marker marker;
  final int endMs;
  final int depth;
  final bool current;
  final bool expanded;
  final VoidCallback onToggle;
  final bool Function(MarkerOutcome outcome, MarkerTier tier) check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(practiceControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = marker.tier;
    final isMark = tier == MarkerTier.mark;

    Future<void> rename() async {
      final label = await promptText(
        context,
        title: 'Rename ${isMark ? 'mark' : 'minimark'}',
        initial: marker.label,
        hint: 'Label',
      );
      if (label != null) check(controller.renameMarker(marker.id, label), tier);
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0, top: depth == 0 ? 0 : 4),
      child: Card(
        color: current ? scheme.secondaryContainer : (isMark ? null : scheme.surfaceContainerLowest),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              dense: !isMark,
              onTap: () {
                unawaited(controller.seek(marker.positionMs));
                onToggle();
              },
              leading: GestureDetector(
                onTap: rename,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 36),
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isMark ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    marker.label.isEmpty ? '·' : marker.label,
                    style: TextStyle(
                      color: isMark ? scheme.onTertiaryContainer : scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              title: Text(
                '${formatMs(marker.positionMs, tenths: true)} → ${formatMs(endMs, tenths: true)}',
                style: tabular(theme.textTheme.bodyLarge),
              ),
              subtitle: Text(
                '${formatSeconds(endMs - marker.positionMs)}'
                '${marker.skip ? ' · skipped' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Play this segment once',
                    onPressed: () => unawaited(
                      controller.playRangeOnce(marker.positionMs, endMs),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    tooltip: 'Loop this segment',
                    onPressed: () => unawaited(
                      controller.loopRange(marker.positionMs, endMs),
                    ),
                    icon: const Icon(Icons.loop),
                  ),
                ],
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    HoldIconButton(
                      icon: Icons.remove,
                      tooltip: 'Nudge 100 ms earlier',
                      size: 36,
                      onStep: (m) => check(controller.nudgeMarker(marker.id, -100 * m), tier),
                    ),
                    HoldIconButton(
                      icon: Icons.add,
                      tooltip: 'Nudge 100 ms later',
                      size: 36,
                      onStep: (m) => check(controller.nudgeMarker(marker.id, 100 * m), tier),
                    ),
                    FilterChip(
                      label: const Text('Skip'),
                      selected: marker.skip,
                      onSelected: (_) => check(controller.toggleSkip(marker.id), tier),
                    ),
                    ActionChip(label: const Text('Rename'), onPressed: rename),
                    ActionChip(
                      label: const Text('Set time…'),
                      onPressed: () async {
                        final ms = await promptTime(
                          context,
                          title: 'Marker time',
                          initialMs: marker.positionMs,
                          maxMs: ref.read(engineProvider).state.durationMs,
                        );
                        if (ms != null) check(controller.moveMarker(marker.id, ms), tier);
                      },
                    ),
                    ActionChip(
                      label: const Text('To playhead'),
                      onPressed: () => check(
                        controller.moveMarker(marker.id, ref.read(engineProvider).positionMs),
                        tier,
                      ),
                    ),
                    ActionChip(
                      label: Text('Delete', style: TextStyle(color: scheme.error)),
                      onPressed: () => check(controller.removeMarker(marker.id), tier),
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

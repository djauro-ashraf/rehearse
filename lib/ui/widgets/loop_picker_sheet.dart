import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/ids.dart';
import '../../core/material.dart';
import '../../domain/routine.dart';
import '../../state/library_notifier.dart';
import 'small_widgets.dart';

/// Lets the user tick loops (or whole tracks) from anywhere in the library.
/// Returns the chosen steps, or null if cancelled.
Future<List<RoutineStep>?> showLoopPicker(BuildContext context) {
  return showModalBottomSheet<List<RoutineStep>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          _LoopPicker(scrollController: scrollController),
    ),
  );
}

class _LoopPicker extends ConsumerStatefulWidget {
  const _LoopPicker({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_LoopPicker> createState() => _LoopPickerState();
}

class _LoopPickerState extends ConsumerState<_LoopPicker> {
  // (trackId, loopId) — loopId null means the whole track.
  final Set<(String, String?)> _selected = {};

  void _toggle((String, String?) key, bool? value) {
    setState(() {
      if (value ?? false) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    if (tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.library_music_outlined,
        title: 'Nothing to add yet',
        message: 'Import a track and save a few loops first.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Add steps', style: theme.textTheme.titleLarge),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            children: [
              for (final track in tracks)
                ExpansionTile(
                  initiallyExpanded: tracks.length == 1 || track.loops.isNotEmpty && tracks.length <= 3,
                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${track.loops.length} ${track.loops.length == 1 ? 'loop' : 'loops'}',
                  ),
                  children: [
                    CheckboxListTile(
                      value: _selected.contains((track.id, null)),
                      onChanged: (v) => _toggle((track.id, null), v),
                      title: const Text('Whole track'),
                      subtitle: Text(formatMs(track.durationMs)),
                    ),
                    for (final loop in [...track.loops]
                      ..sort((a, b) => a.startMs.compareTo(b.startMs)))
                      CheckboxListTile(
                        value: _selected.contains((track.id, loop.id)),
                        onChanged: (v) => _toggle((track.id, loop.id), v),
                        title: Text(loop.name),
                        subtitle: Text(
                          '${formatMs(loop.startMs)} – ${formatMs(loop.endMs)} · ${formatSpeed(loop.speed)}',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () {
                        final steps = <RoutineStep>[];
                        // Keep library order, then loop order within a track.
                        for (final track in tracks) {
                          final loops = [...track.loops]
                            ..sort((a, b) => a.startMs.compareTo(b.startMs));
                          for (final key in <(String, String?)>[
                            (track.id, null),
                            for (final l in loops) (track.id, l.id),
                          ]) {
                            if (!_selected.contains(key)) continue;
                            final loop = track.loopById(key.$2);
                            steps.add(RoutineStep(
                              id: newId(),
                              trackId: track.id,
                              loopId: key.$2,
                              repeats: loop != null && loop.repeats > 0 ? loop.repeats : 3,
                            ));
                          }
                        }
                        Navigator.of(context).pop(steps);
                      },
                child: Text(
                  _selected.isEmpty
                      ? 'Choose loops'
                      : 'Add ${_selected.length} ${_selected.length == 1 ? 'step' : 'steps'}',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/marker.dart';
import '../../domain/track.dart';
import '../../state/library_notifier.dart';
import '../../state/track_actions.dart';
import '../navigation.dart';
import '../widgets/small_widgets.dart';
import '../widgets/track_flows.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  bool _importing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final result = await ref.read(trackActionsProvider).pickAndImport();
      if (!mounted) return;
      if (result.added.length == 1 && result.failed == 0) {
        unawaited(openPractice(context, result.added.first.id));
      } else if (result.added.isNotEmpty || result.failed > 0) {
        final parts = <String>[
          if (result.added.isNotEmpty)
            'Added ${result.added.length} ${result.added.length == 1 ? 'track' : 'tracks'}',
          if (result.failed > 0)
            '${result.failed} could not be read',
        ];
        showSnack(context, parts.join(' · '));
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Couldn’t import that file');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(libraryProvider);
    final query = _search.text.trim().toLowerCase();
    final tracks = [
      for (final t in all)
        if (query.isEmpty || t.title.toLowerCase().contains(query)) t,
    ]..sort((a, b) {
        final byPlayed = b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs);
        return byPlayed != 0 ? byPlayed : b.addedAtMs.compareTo(a.addedAtMs);
      });
    final resume = query.isEmpty && tracks.isNotEmpty && tracks.first.hasBeenPlayed
        ? tracks.first
        : null;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: const Icon(Icons.add),
        label: const Text('Import audio'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: _searching
                ? TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search tracks',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                : const Text('Library'),
            actions: [
              if (all.isNotEmpty)
                IconButton(
                  tooltip: _searching ? 'Close search' : 'Search',
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _search.clear();
                  }),
                  icon: Icon(_searching ? Icons.close : Icons.search),
                ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          if (_importing)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (all.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.library_music_outlined,
                title: 'Bring in something to practise',
                message: 'Import a lesson, a song or a recording. You can also '
                    'open audio from another app with “Open with” or “Share”.',
                action: FilledButton.icon(
                  onPressed: _importing ? null : _import,
                  icon: const Icon(Icons.add),
                  label: const Text('Import audio'),
                ),
              ),
            )
          else if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off,
                title: 'No matches',
                message: 'Try a different search.',
              ),
            )
          else ...[
            if (resume != null)
              SliverToBoxAdapter(child: _ResumeCard(track: resume)),
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) => _TrackTile(track: tracks[index]),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final memory = track.memory;
    final detail = memory.loopOn && memory.hasLoop
        ? 'Loop ${formatMs(memory.loopStartMs!)}–${formatMs(memory.loopEndMs!)} · ${formatSpeed(memory.speed)}'
        : 'Paused at ${formatMs(memory.positionMs)} · ${formatSpeed(memory.speed)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        color: scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(openPractice(context, track.id)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.play_circle_fill_rounded,
                    size: 44, color: scheme.onPrimaryContainer),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parts = <String>[
      formatMs(track.durationMs),
      if (track.loops.isNotEmpty)
        '${track.loops.length} ${track.loops.length == 1 ? 'loop' : 'loops'}',
      if ((track.activeSet?.count(MarkerTier.mark) ?? 0) > 0)
        '${track.activeSet!.count(MarkerTier.mark)} '
            '${track.activeSet!.count(MarkerTier.mark) == 1 ? 'mark' : 'marks'}',
      if (track.hasBeenPlayed) formatAgo(track.lastPlayedAtMs),
    ];
    return ListTile(
      onTap: () => unawaited(openPractice(context, track.id)),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: const Icon(Icons.music_note_rounded),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parts.join(' · ')),
      trailing: PopupMenuButton<String>(
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
              await TrackFlows.delete(context, ref, track);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'share', child: Text('Share practice sheet')),
          PopupMenuItem(value: 'import', child: Text('Import practice sheet')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/material.dart';
import '../../data/audio_importer.dart';
import '../../state/app_providers.dart';
import '../../state/engine_providers.dart';
import '../../state/platform_providers.dart';
import '../../state/practice_controller.dart';
import '../../state/track_actions.dart';
import '../navigation.dart';
import '../widgets/mini_player.dart';
import 'library_screen.dart';
import 'routines_screen.dart';

/// The two main tabs, the mini player, and the app-level plumbing: saving
/// when the app is backgrounded and importing audio shared from other apps.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _askedForNotifications = false;
  StreamSubscription<List<ImportSource>>? _incoming;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final incoming = ref.read(incomingAudioProvider);
    _incoming = incoming.stream.listen((sources) => unawaited(_handleIncoming(sources)));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await incoming.takePending();
      if (pending.isNotEmpty) await _handleIncoming(pending);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_incoming?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    // Anything could happen once we're in the background: save now.
    ref.read(practiceControllerProvider.notifier).persist();
    unawaited(ref.read(documentStoreProvider).flush());
  }

  Future<void> _handleIncoming(List<ImportSource> sources) async {
    final result = await ref.read(trackActionsProvider).importSources(sources);
    if (!mounted) return;
    if (result.added.isNotEmpty) {
      unawaited(openPractice(context, result.added.first.id));
    } else if (result.failed > 0) {
      showSnack(context, 'That file couldn’t be opened as audio');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Android 13+ needs permission to show the media notification. Ask the
    // first time audio actually starts, when the reason is obvious.
    ref.listen(engineStateProvider.select((s) => s.playing), (_, playing) {
      if (playing && !_askedForNotifications) {
        _askedForNotifications = true;
        unawaited(ref.read(incomingAudioProvider).requestNotificationPermission());
      }
    });

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [LibraryScreen(), RoutinesScreen()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.playlist_play_outlined),
                selectedIcon: Icon(Icons.playlist_play),
                label: 'Routines',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

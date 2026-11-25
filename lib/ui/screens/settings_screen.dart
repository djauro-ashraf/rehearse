import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/format.dart';
import '../../core/material.dart';
import '../../data/backup.dart';
import '../../domain/app_settings.dart';
import '../../domain/loop_rules.dart';
import '../../state/app_providers.dart';
import '../../state/settings_notifier.dart';
import '../../state/track_actions.dart';
import '../navigation.dart';
import '../widgets/small_widgets.dart';

class _StorageTile extends ConsumerStatefulWidget {
  const _StorageTile();

  @override
  ConsumerState<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends ConsumerState<_StorageTile> {
  late final Future<int> _bytes = ref.read(audioStorageProvider).totalBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _bytes,
      builder: (context, snapshot) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('Imported audio'),
        subtitle: const Text(
          'Files are copied into the app, so they keep working even if '
          'you move or delete the originals.',
        ),
        trailing: Text(
          snapshot.hasData ? formatBytes(snapshot.data!) : '…',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}

class _RestoreReportDialog extends StatelessWidget {
  const _RestoreReportDialog({required this.report});

  final RestoreReport report;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (report.changedAnything)
        'Added ${report.loopsAdded} loops, ${report.markersAdded} markers and '
            '${report.routinesAdded} routines to ${report.matchedTracks} '
            '${report.matchedTracks == 1 ? 'track' : 'tracks'}.'
      else
        'Everything in this backup is already here.',
      if (report.stepsDropped > 0)
        '${report.stepsDropped} routine steps were skipped because their '
            'audio isn’t in your library yet.',
    ];
    final missing = report.unmatchedTitles;
    return AlertDialog(
      title: Text(report.changedAnything ? 'Restored' : 'Nothing new'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line)),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Not in your library yet (import the audio, then restore again):',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final title in missing.take(8)) Text('• $title'),
              if (missing.length > 8) Text('…and ${missing.length - 8} more'),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          header('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  notifier.update((s) => s.copyWith(themeMode: selection.first)),
            ),
          ),
          header('Practice'),
          SwitchListTile(
            title: const Text('Preview before B'),
            subtitle: const Text(
              'After you set or move B, play the last few seconds before it '
              'so you can hear if the loop ends in the right place.',
            ),
            value: settings.previewEnabled,
            onChanged: (v) => notifier.update((s) => s.copyWith(previewEnabled: v)),
          ),
          if (settings.previewEnabled)
            ListTile(
              title: const Text('Preview length'),
              subtitle: Slider(
                value: settings.previewMs.toDouble(),
                min: LoopRules.minPreviewMs.toDouble(),
                max: LoopRules.maxPreviewMs.toDouble(),
                divisions: (LoopRules.maxPreviewMs - LoopRules.minPreviewMs) ~/ 500,
                label: formatSeconds(settings.previewMs),
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(previewMs: LoopRules.clampPreview(v.round())),
                ),
              ),
              trailing: Text(formatSeconds(settings.previewMs)),
            ),
          ListTile(
            title: const Text('Skip buttons jump'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 5, label: Text('5 s')),
                  ButtonSegment(value: 10, label: Text('10 s')),
                  ButtonSegment(value: 30, label: Text('30 s')),
                ],
                selected: {settings.skipSeconds},
                onSelectionChanged: (selection) =>
                    notifier.update((s) => s.copyWith(skipSeconds: selection.first)),
              ),
            ),
          ),
          ListTile(
            title: const Text('Starting speed'),
            subtitle: Slider(
              value: settings.defaultSpeed,
              min: LoopRules.minSpeed,
              max: LoopRules.maxSpeed,
              divisions: 55,
              label: formatSpeed(settings.defaultSpeed),
              onChanged: (v) => notifier.update(
                (s) => s.copyWith(defaultSpeed: LoopRules.clampSpeed(v)),
              ),
            ),
            trailing: Text(formatSpeed(settings.defaultSpeed)),
          ),
          ListTile(
            title: const Text('Starting pitch'),
            subtitle: const Text('Used the first time you open a track. After that each track remembers its own.'),
            trailing: StepperField(
              display: formatPitch(settings.defaultPitch),
              minusEnabled: settings.defaultPitch > LoopRules.minPitch,
              plusEnabled: settings.defaultPitch < LoopRules.maxPitch,
              onMinus: () => notifier.update(
                (s) => s.copyWith(defaultPitch: LoopRules.clampPitch(s.defaultPitch - 1)),
              ),
              onPlus: () => notifier.update(
                (s) => s.copyWith(defaultPitch: LoopRules.clampPitch(s.defaultPitch + 1)),
              ),
            ),
          ),
          header('Backup'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Back up my practice data'),
            subtitle: const Text(
              'Saves every loop, stamp set and routine to one file (not the audio).',
            ),
            onTap: () async {
              try {
                await ref.read(trackActionsProvider).shareBackup();
              } catch (_) {
                if (context.mounted) showSnack(context, 'Couldn’t create the backup');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore from a backup'),
            subtitle: const Text(
              'Matches tracks by content, or by name and length. Import the '
              'audio first; restoring again later only adds what is missing.',
            ),
            onTap: () async {
              try {
                final report = await ref.read(trackActionsProvider).restoreBackup();
                if (report == null || !context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => _RestoreReportDialog(report: report),
                );
              } on FormatException catch (e) {
                if (context.mounted) showSnack(context, e.message);
              } catch (_) {
                if (context.mounted) showSnack(context, 'Couldn’t read that file');
              }
            },
          ),
          header('Storage'),
          const _StorageTile(),
          header('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(appName),
            subtitle: Text('Version $appVersion'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

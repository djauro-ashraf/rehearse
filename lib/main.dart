import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/material.dart';
import 'data/audio_storage.dart';
import 'data/document_store.dart';
import 'engine/drill_engine.dart';
import 'platform/just_audio_backend.dart';
import 'platform/media_handler.dart';
import 'state/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything the first frame needs is loaded before runApp, so no screen
  // ever shows a spinner for its own data.
  final root = await getApplicationDocumentsDirectory();
  final store = FileDocumentStore(Directory(p.join(root.path, 'data')));
  final storage = AudioStorage(Directory(p.join(root.path, 'audio')));
  await storage.ensureCreated();
  final startup = await StartupData.load(store);

  final engine = DrillEngine(JustAudioBackend());
  await AudioService.init<RehearseAudioHandler>(
    builder: () => RehearseAudioHandler(engine),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.rehearse.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationIcon: 'drawable/ic_stat_rehearse',
      // Stay a foreground service while paused so Android doesn't reclaim the
      // app when you switch to another one mid-practice. RehearseAudioHandler
      // releases it after 15 idle minutes.
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        startupDataProvider.overrideWithValue(startup),
        documentStoreProvider.overrideWithValue(store),
        audioStorageProvider.overrideWithValue(storage),
        engineProvider.overrideWithValue(engine),
      ],
      child: const RehearseApp(),
    ),
  );
}

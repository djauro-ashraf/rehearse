import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audio_importer.dart';
import '../platform/file_service.dart';
import '../platform/incoming_audio.dart';
import '../platform/just_audio_backend.dart';
import 'app_providers.dart';

/// Providers that wrap Flutter plugins. Kept apart from the rest of the state
/// layer so that layer stays plain Dart (and unit-testable without a device).
final fileServiceProvider = Provider<FileService>((ref) => const FileService());

final incomingAudioProvider = Provider<IncomingAudio>((ref) => IncomingAudio());

final audioImporterProvider = Provider<AudioImporter>(
  (ref) => AudioImporter(
    storage: ref.watch(audioStorageProvider),
    probe: JustAudioBackend.probeDurationMs,
  ),
);

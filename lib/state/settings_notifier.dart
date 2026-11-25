import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_settings.dart';
import 'app_providers.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(startupDataProvider).settings;

  void update(AppSettings Function(AppSettings current) change) {
    state = change(state);
    ref.read(documentStoreProvider).write('settings', state.toJson());
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// How far the ± skip buttons jump, in seconds.
final skipSecondsProvider = Provider<int>(
  (ref) => ref.watch(settingsProvider.select((s) => s.skipSeconds)),
);

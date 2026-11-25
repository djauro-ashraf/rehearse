import 'dart:async';

import 'package:flutter/services.dart';

import '../data/audio_importer.dart';

/// Audio handed to the app from outside ("Open with…", "Share to…").
///
/// Android copies the shared file into the app's cache (see MainActivity.kt)
/// and queues it here. Every method is safe to call on platforms without the
/// native side: they simply do nothing.
class IncomingAudio {
  IncomingAudio() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingChanged') unawaited(_drain());
    });
  }

  static const MethodChannel _channel = MethodChannel('app.rehearse/platform');

  final StreamController<List<ImportSource>> _controller =
      StreamController<List<ImportSource>>.broadcast();

  /// Emits whenever the app receives audio while it is running.
  Stream<List<ImportSource>> get stream => _controller.stream;

  /// Audio that arrived before the app was ready (cold start).
  Future<List<ImportSource>> takePending() async {
    try {
      final result = await _channel.invokeListMethod<Map<Object?, Object?>>('takePending');
      return _parse(result ?? const []);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Android 13+ needs a runtime permission for the media notification.
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on MissingPluginException {
      // Not Android.
    } on PlatformException {
      // Ignore: playback works without the notification.
    }
  }

  Future<void> _drain() async {
    final items = await takePending();
    if (items.isNotEmpty) _controller.add(items);
  }

  static List<ImportSource> _parse(List<Map<Object?, Object?>> raw) => [
        for (final item in raw)
          if (item['path'] is String)
            ImportSource(
              name: (item['name'] as String?) ?? 'Audio',
              path: item['path']! as String,
              isTemporary: true,
            ),
      ];
}

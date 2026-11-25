import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_state.dart';
import 'app_providers.dart';

/// The engine's state as a Riverpod provider. (The playhead position is not
/// part of it; widgets that need it listen to `engine.positions` directly.)
class EngineStateNotifier extends Notifier<EngineState> {
  @override
  EngineState build() {
    final engine = ref.watch(engineProvider);
    final subscription = engine.states.listen((s) => state = s);
    ref.onDispose(subscription.cancel);
    return engine.state;
  }
}

final engineStateProvider =
    NotifierProvider<EngineStateNotifier, EngineState>(EngineStateNotifier.new);

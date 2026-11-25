import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/material.dart';
import '../../state/app_providers.dart';

/// Rebuilds [builder] with the playhead position, ~30 times a second, without
/// touching the rest of the screen.
class PositionBuilder extends ConsumerWidget {
  const PositionBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, int positionMs) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider);
    return StreamBuilder<int>(
      stream: engine.positions,
      initialData: engine.positionMs,
      builder: (context, snapshot) =>
          builder(context, snapshot.data ?? engine.positionMs),
    );
  }
}

import 'dart:async';

import '../../core/material.dart';

/// A round ± button that repeats while held, speeding up the longer you hold.
/// [onStep] receives a multiplier (1, then 5, then 10).
class HoldIconButton extends StatefulWidget {
  const HoldIconButton({
    super.key,
    required this.icon,
    required this.onStep,
    required this.tooltip,
    this.enabled = true,
    this.size = 44,
  });

  final IconData icon;
  final void Function(int multiplier) onStep;
  final String tooltip;
  final bool enabled;
  final double size;

  @override
  State<HoldIconButton> createState() => _HoldIconButtonState();
}

class _HoldIconButtonState extends State<HoldIconButton> {
  Timer? _timer;
  int _ticks = 0;

  void _startRepeating() {
    if (!widget.enabled) return;
    _ticks = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      _ticks++;
      widget.onStep(_ticks < 8 ? 1 : (_ticks < 20 ? 5 : 10));
    });
  }

  void _stopRepeating() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onStep(1) : null,
          onLongPressStart: (_) => _startRepeating(),
          onLongPressEnd: (_) => _stopRepeating(),
          onLongPressCancel: _stopRepeating,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? scheme.secondaryContainer
                  : scheme.onSurface.withValues(alpha: 0.08),
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.5,
              color: enabled
                  ? scheme.onSecondaryContainer
                  : scheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
      ),
    );
  }
}

/// `−  value  +` with a fixed-width, non-jiggling value.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.display,
    required this.onMinus,
    required this.onPlus,
    this.minusEnabled = true,
    this.plusEnabled = true,
    this.valueWidth = 72,
  });

  final String display;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final bool minusEnabled;
  final bool plusEnabled;
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Decrease',
          onPressed: minusEnabled ? onMinus : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(
            display,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Increase',
          onPressed: plusEnabled ? onPlus : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// A rounded section with a title.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

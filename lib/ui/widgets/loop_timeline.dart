import 'dart:math' as math;

import '../../core/format.dart';
import '../../core/material.dart';
import '../../domain/loop_rules.dart';
import '../theme.dart';

enum _Drag { none, scrub, handleA, handleB }

/// The track as a horizontal strip: playhead, draggable A/B handles, saved
/// loops, markers. Tap or drag to seek; drag a handle to move it.
class LoopTimeline extends StatefulWidget {
  const LoopTimeline({
    super.key,
    required this.durationMs,
    required this.positionMs,
    required this.loopOn,
    required this.locked,
    required this.zoomToLoop,
    required this.onSeek,
    required this.onRegionChanged,
    required this.onRegionChangeEnd,
    this.loopStartMs,
    this.loopEndMs,
    this.markerPositions = const [],
    this.minimarkPositions = const [],
    this.savedRegions = const [],
  });

  final int durationMs;
  final int positionMs;
  final int? loopStartMs;
  final int? loopEndMs;
  final bool loopOn;

  /// When true the handles can't be grabbed (the strip only seeks).
  final bool locked;

  /// Shows only the loop and a little context around it.
  final bool zoomToLoop;
  final List<int> markerPositions;
  final List<int> minimarkPositions;
  final List<(int, int)> savedRegions;

  final void Function(int ms) onSeek;
  final void Function(int startMs, int endMs) onRegionChanged;
  final void Function({required bool movedB}) onRegionChangeEnd;

  @override
  State<LoopTimeline> createState() => _LoopTimelineState();
}

class _LoopTimelineState extends State<LoopTimeline> {
  static const double _height = 96;
  static const double _grabRadius = 30;

  _Drag _drag = _Drag.none;
  int? _scrubMs;
  (int, int)? _frozenWindow;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _hasLoop => widget.loopStartMs != null && widget.loopEndMs != null;

  /// The visible time range.
  (int, int) get _window {
    if (_frozenWindow != null) return _frozenWindow!;
    final duration = math.max(1, widget.durationMs);
    if (!widget.zoomToLoop || !_hasLoop) return (0, duration);
    final a = widget.loopStartMs!;
    final b = widget.loopEndMs!;
    final pad = math.max(2000, ((b - a) * 0.5).round());
    final start = math.max(0, a - pad);
    final end = math.min(duration, b + pad);
    return end - start < LoopRules.minLoopMs * 2 ? (0, duration) : (start, end);
  }

  double _xFor(int ms, double width) {
    final (start, end) = _window;
    return ((ms - start) / (end - start)).clamp(-0.05, 1.05) * width;
  }

  int _msAt(double x, double width) {
    final (start, end) = _window;
    final ratio = (x / width).clamp(0.0, 1.0);
    return (start + ratio * (end - start)).round().clamp(0, widget.durationMs);
  }

  void _onStart(DragStartDetails details, double width) {
    _frozenWindow = _window;
    final x = details.localPosition.dx;
    if (!widget.locked && _hasLoop) {
      final da = (x - _xFor(widget.loopStartMs!, width)).abs();
      final db = (x - _xFor(widget.loopEndMs!, width)).abs();
      if (math.min(da, db) <= _grabRadius) {
        _drag = da < db ? _Drag.handleA : _Drag.handleB;
        return;
      }
    }
    _drag = _Drag.scrub;
    _scrub(x, width, force: true);
  }

  void _onUpdate(DragUpdateDetails details, double width) {
    final x = details.localPosition.dx;
    switch (_drag) {
      case _Drag.handleA:
        final end = widget.loopEndMs!;
        widget.onRegionChanged(
          LoopRules.clampStart(_msAt(x, width), end),
          end,
        );
      case _Drag.handleB:
        final start = widget.loopStartMs!;
        widget.onRegionChanged(
          start,
          LoopRules.clampEnd(_msAt(x, width), start, widget.durationMs),
        );
      case _Drag.scrub:
        _scrub(x, width);
      case _Drag.none:
        break;
    }
  }

  void _onEnd(double width) {
    final finished = _drag;
    if (finished == _Drag.scrub && _scrubMs != null) widget.onSeek(_scrubMs!);
    setState(() {
      _drag = _Drag.none;
      _scrubMs = null;
      _frozenWindow = null;
    });
    if (finished == _Drag.handleA) widget.onRegionChangeEnd(movedB: false);
    if (finished == _Drag.handleB) widget.onRegionChangeEnd(movedB: true);
  }

  void _scrub(double x, double width, {bool force = false}) {
    final ms = _msAt(x, width);
    setState(() => _scrubMs = ms);
    final now = DateTime.now();
    if (force || now.difference(_lastSeek).inMilliseconds > 120) {
      _lastSeek = now;
      widget.onSeek(ms);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = PracticeColors.of(context);
    final (windowStart, windowEnd) = _window;
    final labelStyle = tabular(
      Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
    );

    return Semantics(
      label: 'Timeline. Drag to seek.',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => widget.onSeek(_msAt(d.localPosition.dx, width)),
                onHorizontalDragStart: (d) => _onStart(d, width),
                onHorizontalDragUpdate: (d) => _onUpdate(d, width),
                onHorizontalDragEnd: (_) => _onEnd(width),
                onHorizontalDragCancel: () => _onEnd(width),
                child: CustomPaint(
                  size: Size(width, _height),
                  painter: _TimelinePainter(
                    window: (windowStart, windowEnd),
                    positionMs: _scrubMs ?? widget.positionMs,
                    loopStartMs: widget.loopStartMs,
                    loopEndMs: widget.loopEndMs,
                    loopOn: widget.loopOn,
                    locked: widget.locked,
                    dragging: _drag == _Drag.handleA || _drag == _Drag.handleB,
                    markers: widget.markerPositions,
                    minimarks: widget.minimarkPositions,
                    saved: widget.savedRegions,
                    scheme: scheme,
                    colors: colors,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatMs(windowStart), style: labelStyle),
              Text(formatMs(windowEnd), style: labelStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.window,
    required this.positionMs,
    required this.loopStartMs,
    required this.loopEndMs,
    required this.loopOn,
    required this.locked,
    required this.dragging,
    required this.markers,
    required this.minimarks,
    required this.saved,
    required this.scheme,
    required this.colors,
  });

  final (int, int) window;
  final int positionMs;
  final int? loopStartMs;
  final int? loopEndMs;
  final bool loopOn;
  final bool locked;
  final bool dragging;
  final List<int> markers;
  final List<int> minimarks;
  final List<(int, int)> saved;
  final ColorScheme scheme;
  final PracticeColors colors;

  double _x(int ms, double width) {
    final (start, end) = window;
    return ((ms - start) / (end - start)).clamp(0.0, 1.0) * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    const top = 18.0;
    final bottom = size.height - 10;
    final track = RRect.fromLTRBR(0, top, width, bottom, const Radius.circular(14));

    // Track background, and the part already played.
    canvas.drawRRect(track, Paint()..color = scheme.surfaceContainerHighest);
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(
      Rect.fromLTRB(0, top, _x(positionMs, width), bottom),
      Paint()..color = scheme.primary.withValues(alpha: 0.12),
    );

    // Saved loops as thin strips along the bottom edge.
    final savedPaint = Paint()..color = scheme.outline.withValues(alpha: 0.55);
    for (final (a, b) in saved) {
      final left = _x(a, width);
      final right = math.max(left + 2, _x(b, width));
      canvas.drawRect(Rect.fromLTRB(left, bottom - 4, right, bottom), savedPaint);
    }

    // Active loop.
    final a = loopStartMs;
    final b = loopEndMs;
    if (a != null && b != null) {
      final left = _x(a, width);
      final right = math.max(left + 2, _x(b, width));
      final active = loopOn;
      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        Paint()
          ..color = active
              ? colors.loopFill
              : scheme.onSurface.withValues(alpha: 0.06),
      );
      final edge = Paint()
        ..color = active ? colors.loop : scheme.outline
        ..strokeWidth = 2;
      canvas.drawLine(Offset(left, top), Offset(right, top), edge);
      canvas.drawLine(Offset(left, bottom), Offset(right, bottom), edge);
    }
    canvas.restore();

    // Markers.
    final markerPaint = Paint()
      ..color = colors.marker
      ..strokeWidth = 1.5;
    for (final marker in markers) {
      if (marker < window.$1 || marker > window.$2) continue;
      final x = _x(marker, width);
      canvas.drawLine(Offset(x, top + 6), Offset(x, bottom - 4), markerPaint);
      final flag = Path()
        ..moveTo(x, top)
        ..lineTo(x + 8, top + 4)
        ..lineTo(x, top + 8)
        ..close();
      canvas.drawPath(flag, Paint()..color = colors.marker);
    }

    // Minimarks: short ticks, quieter than Marks.
    final miniPaint = Paint()
      ..color = colors.marker.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (final marker in minimarks) {
      if (marker < window.$1 || marker > window.$2) continue;
      final x = _x(marker, width);
      canvas.drawLine(Offset(x, bottom - 14), Offset(x, bottom - 3), miniPaint);
    }

    // A / B handles.
    if (a != null && b != null) {
      final active = loopOn;
      final handleColor = active ? colors.loop : scheme.outline;
      for (final (ms, label) in [(a, 'A'), (b, 'B')]) {
        final x = _x(ms, width);
        canvas.drawLine(
          Offset(x, top - 4),
          Offset(x, bottom),
          Paint()
            ..color = handleColor
            ..strokeWidth = dragging ? 4 : 3
            ..strokeCap = StrokeCap.round,
        );
        // Grip
        final center = Offset(x, (top + bottom) / 2);
        if (!locked) {
          canvas.drawCircle(center, 13, Paint()..color = handleColor);
          final painter = TextPainter(
            text: TextSpan(
              text: label,
              style: TextStyle(
                color: scheme.surface,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(
            canvas,
            center - Offset(painter.width / 2, painter.height / 2),
          );
        }
      }
    }

    // Playhead.
    final px = _x(positionMs, width);
    canvas.drawLine(
      Offset(px, 6),
      Offset(px, bottom + 4),
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(px, 8), 6, Paint()..color = scheme.primary);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.window != window ||
      old.positionMs != positionMs ||
      old.loopStartMs != loopStartMs ||
      old.loopEndMs != loopEndMs ||
      old.loopOn != loopOn ||
      old.locked != locked ||
      old.dragging != dragging ||
      old.markers != markers ||
      old.minimarks != minimarks ||
      old.saved != saved ||
      old.scheme != scheme;
}

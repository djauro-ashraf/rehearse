import '../core/material.dart';

const Color _seed = Color(0xFF0F766E);

/// Colours that only this app needs: the loop band, markers and playhead.
@immutable
class PracticeColors extends ThemeExtension<PracticeColors> {
  const PracticeColors({
    required this.loop,
    required this.loopFill,
    required this.marker,
  });

  final Color loop;
  final Color loopFill;
  final Color marker;

  static PracticeColors of(BuildContext context) =>
      Theme.of(context).extension<PracticeColors>()!;

  @override
  PracticeColors copyWith({Color? loop, Color? loopFill, Color? marker}) =>
      PracticeColors(
        loop: loop ?? this.loop,
        loopFill: loopFill ?? this.loopFill,
        marker: marker ?? this.marker,
      );

  @override
  PracticeColors lerp(ThemeExtension<PracticeColors>? other, double t) {
    if (other is! PracticeColors) return this;
    return PracticeColors(
      loop: Color.lerp(loop, other.loop, t)!,
      loopFill: Color.lerp(loopFill, other.loopFill, t)!,
      marker: Color.lerp(marker, other.marker, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final dark = brightness == Brightness.dark;
  final colors = PracticeColors(
    loop: dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    loopFill: (dark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B))
        .withValues(alpha: dark ? 0.22 : 0.24),
    marker: scheme.tertiary,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [colors],
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: shape,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
  );
}

/// Digits that don't jiggle as they change (times, counters).
TextStyle tabular(TextStyle? base) => (base ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

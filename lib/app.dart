import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_info.dart';
import 'core/material.dart';
import 'domain/app_settings.dart';
import 'state/settings_notifier.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme.dart';

class RehearseApp extends ConsumerWidget {
  const RehearseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      builder: (context, child) => _KeepAboveSystemBars(child: child!),
      home: const HomeShell(),
    );
  }
}

/// Android draws apps edge-to-edge (behind the navigation buttons or gesture
/// bar). Rehearse instead ends *above* them, on every screen: one place, so no
/// individual screen has to remember.
///
/// The top is left alone: app bars already handle the status bar themselves.
class _KeepAboveSystemBars extends StatelessWidget {
  const _KeepAboveSystemBars({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconBrightness =
        scheme.brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Keeps the navigation icons readable against the app's own colour
      // (Android 15+ ignores the bar colour but honours the icon brightness).
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
      ),
      child: ColoredBox(
        color: scheme.surface,
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}

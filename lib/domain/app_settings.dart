import '../core/json.dart';
import 'loop_rules.dart';
import 'speed_trainer.dart';

enum AppThemeMode { system, light, dark }

/// User preferences. Deliberately short: everything that is specific to a
/// passage (speed, pitch, repeats…) lives on the loop, not here.
final class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.previewEnabled = true,
    this.previewMs = 5000,
    this.skipSeconds = 5,
    this.defaultSpeed = 1.0,
    this.defaultPitch = 0.0,
    this.trainer = const SpeedTrainer(),
  });

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == asString(json['themeMode']),
          orElse: () => AppThemeMode.system,
        ),
        previewEnabled: asBool(json['previewEnabled'], true),
        previewMs: LoopRules.clampPreview(asInt(json['previewMs'], 5000)),
        skipSeconds: asInt(json['skipSeconds'], 5).clamp(1, 60),
        defaultSpeed: LoopRules.clampSpeed(asDouble(json['defaultSpeed'], 1.0)),
        defaultPitch: LoopRules.clampPitch(asDouble(json['defaultPitch'])),
        trainer: SpeedTrainer.fromJson(json['trainer']),
      );

  final AppThemeMode themeMode;

  /// After you set or drag B, play the last few seconds before it so you can
  /// hear whether the loop ends in the right place.
  final bool previewEnabled;
  final int previewMs;

  /// How far the ± skip buttons jump.
  final int skipSeconds;

  /// Speed and pitch a track starts with the first time you open it.
  final double defaultSpeed;
  final double defaultPitch;

  /// Last-used speed-trainer setup (applied from the practice screen).
  final SpeedTrainer trainer;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? previewEnabled,
    int? previewMs,
    int? skipSeconds,
    double? defaultSpeed,
    double? defaultPitch,
    SpeedTrainer? trainer,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        previewEnabled: previewEnabled ?? this.previewEnabled,
        previewMs: previewMs ?? this.previewMs,
        skipSeconds: skipSeconds ?? this.skipSeconds,
        defaultSpeed: defaultSpeed ?? this.defaultSpeed,
        defaultPitch: defaultPitch ?? this.defaultPitch,
        trainer: trainer ?? this.trainer,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'previewEnabled': previewEnabled,
        'previewMs': previewMs,
        'skipSeconds': skipSeconds,
        'defaultSpeed': defaultSpeed,
        'defaultPitch': defaultPitch,
        'trainer': trainer.toJson(),
      };
}

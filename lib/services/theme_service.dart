import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themePreferencesNotifier = ThemePreferencesNotifier();

enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromStorage(String? value) {
    return switch (value) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }

  ThemeMode get materialThemeMode => switch (this) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  String get storageValue => switch (this) {
    AppThemeMode.light => 'light',
    AppThemeMode.dark => 'dark',
    AppThemeMode.system => 'system',
  };
}

@immutable
class ThemePreferences {
  const ThemePreferences({
    this.mode = AppThemeMode.system,
    this.seedColor,
    this.dynamicColorEnabled = false,
    this.dynamicColorSupported = false,
    this.predictiveBackEnabled = true,
    this.pureBlackEnabled = false,
  });

  final AppThemeMode mode;
  final Color? seedColor;
  final bool dynamicColorEnabled;
  final bool dynamicColorSupported;
  final bool predictiveBackEnabled;
  final bool pureBlackEnabled;

  bool get useDynamicColors => dynamicColorEnabled && dynamicColorSupported;

  ThemePreferences copyWith({
    AppThemeMode? mode,
    Color? seedColor,
    bool? dynamicColorEnabled,
    bool? dynamicColorSupported,
    bool? predictiveBackEnabled,
    bool? pureBlackEnabled,
  }) {
    return ThemePreferences(
      pureBlackEnabled: pureBlackEnabled ?? this.pureBlackEnabled,
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      dynamicColorEnabled: dynamicColorEnabled ?? this.dynamicColorEnabled,
      dynamicColorSupported:
          dynamicColorSupported ?? this.dynamicColorSupported,
      predictiveBackEnabled:
          predictiveBackEnabled ?? this.predictiveBackEnabled,
    );
  }
}

class ThemePreferencesNotifier extends ValueNotifier<ThemePreferences> {
  ThemePreferencesNotifier() : super(const ThemePreferences());

  Future<void> initialize() async {
    await load();
    await refreshDynamicColorSupport();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var storedMode = prefs.getString('theme_mode');
    var dynamicColorEnabled = prefs.getBool('dynamic_color_enabled') ?? false;
    final predictiveBackEnabled =
        prefs.getBool('predictive_back_enabled') ?? true;

    // 旧版本把动态取色作为 theme_mode 的第四个值保存。
    if (storedMode == 'dynamic') {
      storedMode = AppThemeMode.system.storageValue;
      dynamicColorEnabled = true;
      await prefs.setString('theme_mode', storedMode);
      await prefs.setBool('dynamic_color_enabled', dynamicColorEnabled);
    }

    value = value.copyWith(
      pureBlackEnabled: prefs.getBool('theme_pure_black') ?? false,
      mode: AppThemeMode.fromStorage(storedMode),
      seedColor:
          prefs.getInt('theme_seed_color') == null
              ? null
              : Color(prefs.getInt('theme_seed_color')!),
      dynamicColorEnabled: dynamicColorEnabled,
      predictiveBackEnabled: predictiveBackEnabled,
    );
  }

  Future<void> setSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setInt('theme_seed_color', color.toARGB32()) ||
        !await prefs.setBool('dynamic_color_enabled', false)) {
      throw StateError('theme_write_failed');
    }
    value = value.copyWith(seedColor: color, dynamicColorEnabled: false);
  }

  Future<void> setPureBlackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('theme_pure_black', enabled)) {
      throw StateError('theme_write_failed');
    }
    value = value.copyWith(pureBlackEnabled: enabled);
  }

  Future<void> setMode(AppThemeMode mode) async {
    value = value.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.storageValue);
  }

  Future<void> setDynamicColorEnabled(bool enabled) async {
    if (enabled && !value.dynamicColorSupported) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('dynamic_color_enabled', enabled)) {
      throw StateError('theme_write_failed');
    }
    value = value.copyWith(dynamicColorEnabled: enabled);
  }

  Future<void> setPredictiveBackEnabled(bool enabled) async {
    value = value.copyWith(predictiveBackEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('predictive_back_enabled', enabled);
  }

  Future<void> refreshDynamicColorSupport() async {
    var supported = false;
    try {
      supported = await DynamicColorPlugin.getCorePalette() != null;
    } on PlatformException {
      supported = false;
    }

    final enabled = value.dynamicColorEnabled && supported;
    value = value.copyWith(
      dynamicColorEnabled: enabled,
      dynamicColorSupported: supported,
    );

    if (!supported) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dynamic_color_enabled', false);
    }
  }
}

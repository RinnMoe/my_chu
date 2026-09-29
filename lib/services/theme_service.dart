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
    this.dynamicColorEnabled = false,
    this.dynamicColorSupported = false,
    this.predictiveBackEnabled = true,
  });

  final AppThemeMode mode;
  final bool dynamicColorEnabled;
  final bool dynamicColorSupported;
  final bool predictiveBackEnabled;

  bool get useDynamicColors => dynamicColorEnabled && dynamicColorSupported;

  ThemePreferences copyWith({
    AppThemeMode? mode,
    bool? dynamicColorEnabled,
    bool? dynamicColorSupported,
    bool? predictiveBackEnabled,
  }) {
    return ThemePreferences(
      mode: mode ?? this.mode,
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
      mode: AppThemeMode.fromStorage(storedMode),
      dynamicColorEnabled: dynamicColorEnabled,
      predictiveBackEnabled: predictiveBackEnabled,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    value = value.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.storageValue);
  }

  Future<void> setDynamicColorEnabled(bool enabled) async {
    if (enabled && !value.dynamicColorSupported) return;
    value = value.copyWith(dynamicColorEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dynamic_color_enabled', enabled);
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

import 'dart:convert';
import 'academic_schedule_style.dart';
import 'academic_schedule_store.dart';
import 'academic_schedule_background_store.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AcademicSchedulePalette {
  classic('classic', '经典浅彩'),
  ocean('ocean', '海盐蓝绿'),
  sunset('sunset', '落日橘粉');

  const AcademicSchedulePalette(this.id, this.label);
  final String id;
  final String label;
}

/// Local display settings only; never part of a campus schedule or export.
@immutable
class AcademicScheduleAppearance {
  const AcademicScheduleAppearance({
    this.palette = AcademicSchedulePalette.classic,
    this.lightColors = const {},
    this.darkColors = const {},
    this.lightBackground,
    this.darkBackground,
    this.lightBackgroundImage,
    this.darkBackgroundImage,
    this.style = const AcademicScheduleStyle(),
  });

  final AcademicSchedulePalette palette;
  final Map<int, Color> lightColors;
  final Map<int, Color> darkColors;
  final Color? lightBackground;
  final Color? darkBackground;
  final String? lightBackgroundImage, darkBackgroundImage;

  String? backgroundImage(bool dark) =>
      dark ? darkBackgroundImage : lightBackgroundImage;
  final AcademicScheduleStyle style;

  AcademicScheduleAppearance withStyle(AcademicScheduleStyle value) =>
      AcademicScheduleAppearance(
        lightBackgroundImage: lightBackgroundImage,
        darkBackgroundImage: darkBackgroundImage,
        palette: palette,
        lightColors: lightColors,
        darkColors: darkColors,
        lightBackground: lightBackground,
        darkBackground: darkBackground,
        style: value,
      );

  AcademicScheduleAppearance withColor(int index, Color color, bool dark) =>
      AcademicScheduleAppearance(
        lightBackgroundImage: lightBackgroundImage,
        darkBackgroundImage: darkBackgroundImage,
        palette: palette,
        style: style,
        lightColors: dark ? lightColors : {...lightColors, index: color},
        darkColors: dark ? {...darkColors, index: color} : darkColors,
        lightBackground: lightBackground,
        darkBackground: darkBackground,
      );

  AcademicScheduleAppearance withoutColor(int index, bool dark) =>
      AcademicScheduleAppearance(
        palette: palette,
        style: style,
        lightBackground: lightBackground,
        darkBackground: darkBackground,
        lightBackgroundImage: lightBackgroundImage,
        darkBackgroundImage: darkBackgroundImage,
        lightColors:
            dark
                ? lightColors
                : (Map<int, Color>.of(lightColors)..remove(index)),
        darkColors:
            dark ? (Map<int, Color>.of(darkColors)..remove(index)) : darkColors,
      );

  AcademicScheduleAppearance withBackground(Color? color, bool dark) =>
      AcademicScheduleAppearance(
        lightBackgroundImage: dark ? lightBackgroundImage : null,
        darkBackgroundImage: dark ? null : darkBackgroundImage,
        palette: palette,
        style: style,
        lightColors: lightColors,
        darkColors: darkColors,
        lightBackground: dark ? lightBackground : color,
        darkBackground: dark ? color : darkBackground,
      );

  AcademicScheduleAppearance withPalette(AcademicSchedulePalette value) =>
      AcademicScheduleAppearance(
        lightBackgroundImage: lightBackgroundImage,
        darkBackgroundImage: darkBackgroundImage,
        palette: value,
        lightBackground: lightBackground,
        darkBackground: darkBackground,
        style: style,
      );

  AcademicScheduleAppearance withBackgroundImage(String image, bool dark) =>
      AcademicScheduleAppearance(
        palette: palette,
        style: style,
        lightColors: lightColors,
        darkColors: darkColors,
        lightBackground: lightBackground,
        darkBackground: darkBackground,
        lightBackgroundImage: dark ? lightBackgroundImage : image,
        darkBackgroundImage: dark ? image : darkBackgroundImage,
      );

  Color canvas(ColorScheme scheme) =>
      (scheme.brightness == Brightness.dark
          ? darkBackground
          : lightBackground) ??
      scheme.surface;

  Map<String, Object?> toJson() => {
    'version': 3,
    'lightBackgroundImage': lightBackgroundImage,
    'darkBackgroundImage': darkBackgroundImage,
    'style': style.toJson(),
    'palette': palette.id,
    'lightColors': {
      for (final e in lightColors.entries) '${e.key}': e.value.toARGB32(),
    },
    'darkColors': {
      for (final e in darkColors.entries) '${e.key}': e.value.toARGB32(),
    },
    'lightBackground': lightBackground?.toARGB32(),
    'darkBackground': darkBackground?.toARGB32(),
  };

  factory AcademicScheduleAppearance.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 && json['version'] != 2 && json['version'] != 3) {
      return const AcademicScheduleAppearance();
    }
    String? readImage(Object? value) =>
        value is String &&
                RegExp(r'^background_[a-f0-9]{64}\.png$').hasMatch(value)
            ? value
            : null;
    Color? readColor(Object? value) =>
        value is int && value >= 0xff000000 && value <= 0xffffffff
            ? Color(value)
            : null;
    Map<int, Color> readColors(Object? raw) {
      if (raw is! Map) return const {};
      final result = <int, Color>{};
      for (final entry in raw.entries) {
        final index = int.tryParse('${entry.key}');
        final color = readColor(entry.value);
        if (index != null && index >= 0 && index < 15 && color != null) {
          result[index] = color;
        }
      }
      return Map.unmodifiable(result);
    }

    // The retired fresh preset maps to classic; preserve user overrides.
    final paletteId = json['palette'] == 'fresh' ? 'classic' : json['palette'];
    final palette =
        AcademicSchedulePalette.values
            .where((value) => value.id == paletteId)
            .firstOrNull;
    if (palette == null) return const AcademicScheduleAppearance();
    return AcademicScheduleAppearance(
      palette: palette,
      lightBackgroundImage: readImage(json['lightBackgroundImage']),
      darkBackgroundImage: readImage(json['darkBackgroundImage']),
      style: AcademicScheduleStyle.fromJson(json['style']),
      lightColors: readColors(json['lightColors']),
      darkColors: readColors(json['darkColors']),
      lightBackground: readColor(json['lightBackground']),
      darkBackground: readColor(json['darkBackground']),
    );
  }
}

class AcademicScheduleAppearanceStore {
  static const storageKey = 'preferences.v1.schedule.appearance';

  static Future<AcademicScheduleAppearance> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(storageKey);
    if (raw is! String) return const AcademicScheduleAppearance();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return AcademicScheduleAppearance.fromJson(json);
      }
    } on FormatException {
      // An invalid appearance must never prevent opening the timetable.
    }
    return const AcademicScheduleAppearance();
  }

  static Future<void> save(AcademicScheduleAppearance value) async {
    final previous = await read();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(storageKey, jsonEncode(value.toJson()))) {
      throw StateError('appearance_write_failed');
    }
    AcademicScheduleDisplayPreferences.revision.value++;
    for (final image
        in {
          previous.lightBackgroundImage,
          previous.darkBackgroundImage,
        }.nonNulls) {
      await discardUnusedBackground(image);
    }
  }

  static Future<void> discardUnusedBackground(String image) async {
    try {
      final saved = await read();
      if (saved.lightBackgroundImage == image ||
          saved.darkBackgroundImage == image) {
        return;
      }
      final file = await AcademicScheduleBackgroundStore.file(image);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup never changes the result of an already persisted preference.
    }
  }
}

class AcademicScheduleAppearanceScope extends InheritedWidget {
  const AcademicScheduleAppearanceScope({
    super.key,
    required this.appearance,
    required super.child,
  });

  final AcademicScheduleAppearance appearance;

  static AcademicScheduleAppearance of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AcademicScheduleAppearanceScope>()
          ?.appearance ??
      const AcademicScheduleAppearance();

  @override
  bool updateShouldNotify(AcademicScheduleAppearanceScope oldWidget) =>
      appearance != oldWidget.appearance;
}

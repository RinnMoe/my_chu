/// MyCHU 主题色系统。
///
/// 以长安大学品牌深蓝 [#0A5CAD] 为种子，按 Material 3 生成完整色板：
/// 五组色调阶梯（主色 / 次色 / 强调色 / 中性 / 错误）、明暗两套 ColorScheme、
/// 语义状态色与品牌渐变。设计依据见 doc/core/interaction_design.md（深蓝 + 浅蓝
/// #E5EEFF、暖白背景、深灰正文；深色模式为浅蓝主色 + 深蓝容器）。
library;

import 'package:flutter/material.dart';

/// 品牌锚点色。
abstract final class AppBrand {
  /// 种子色（品牌深蓝）。
  static const Color seed = Color(0xFF0A5CAD);

  /// 品牌浅蓝（亮色主色容器 / 固定色）。
  static const Color light = Color(0xFFE5EEFF);

  /// 深色模式主色。
  static const Color darkPrimary = Color(0xFFA9C7F2);

  /// 主色固定暗调。
  static const Color fixedDim = Color(0xFFB7CFF2);

  /// 深色海军蓝（亮色主色容器文字）。
  static const Color navy = Color(0xFF001E3B);
}

/// 色调阶梯（M3 HCT 生成，各 10 级）。
///
/// - 主色：种子色相 261°，高彩度品牌蓝；
/// - 次色：与主色同色相、去饱和（M3 标准）；
/// - 强调色：M3 标准强调色相（+60°），偏紫的柔和色；
/// - 中性 / 中性变化：种子色相 261° 的冷色中性，背景为冷白、文字为冷灰；
/// - 错误：M3 标准错误色相。
abstract final class AppPalette {
  static const Map<int, Color> primary = {
    10: Color(0xFF001B3C),
    20: Color(0xFF003061),
    30: Color(0xFF004689),
    40: Color(0xFF245FA6),
    50: Color(0xFF4378C1),
    60: Color(0xFF5F92DD),
    70: Color(0xFF7AADFA),
    80: Color(0xFFA7C8FF),
    90: Color(0xFFD5E3FF),
    95: Color(0xFFECF1FF),
  };

  static const Map<int, Color> secondary = {
    10: Color(0xFF121C2B),
    20: Color(0xFF273141),
    30: Color(0xFF3D4758),
    40: Color(0xFF555F71),
    50: Color(0xFF6E778A),
    60: Color(0xFF8791A5),
    70: Color(0xFFA2ABC0),
    80: Color(0xFFBDC7DC),
    90: Color(0xFFD9E3F8),
    95: Color(0xFFECF1FF),
  };

  static const Map<int, Color> tertiary = {
    10: Color(0xFF28132F),
    20: Color(0xFF3E2845),
    30: Color(0xFF563E5D),
    40: Color(0xFF6E5675),
    50: Color(0xFF886E8F),
    60: Color(0xFFA387AA),
    70: Color(0xFFBFA2C5),
    80: Color(0xFFDBBCE1),
    90: Color(0xFFF8D8FE),
    95: Color(0xFFFEEBFF),
  };

  static const Map<int, Color> neutral = {
    4: Color(0xFF0D0E11),
    6: Color(0xFF121316),
    9: Color(0xFF181A1C),
    10: Color(0xFF1A1C1E),
    12: Color(0xFF1E2023),
    16: Color(0xFF27282B),
    20: Color(0xFF2F3033),
    24: Color(0xFF38393C),
    30: Color(0xFF46474A),
    40: Color(0xFF5E5E62),
    50: Color(0xFF76777A),
    60: Color(0xFF909094),
    70: Color(0xFFABABAF),
    80: Color(0xFFC7C6CA),
    87: Color(0xFFDAD9DD),
    90: Color(0xFFE3E2E6),
    92: Color(0xFFE9E7EB),
    94: Color(0xFFEEEDF1),
    95: Color(0xFFF1F0F4),
    96: Color(0xFFF4F3F7),
    97: Color(0xFFF7F6FA),
    100: Color(0xFFFFFFFF),
  };

  static const Map<int, Color> neutralVariant = {
    10: Color(0xFF181C22),
    20: Color(0xFF2D3038),
    30: Color(0xFF43474E),
    40: Color(0xFF5B5E66),
    50: Color(0xFF74777F),
    60: Color(0xFF8E9199),
    70: Color(0xFFA8ABB4),
    80: Color(0xFFC4C6CF),
    90: Color(0xFFE0E2EC),
    95: Color(0xFFEEF0FA),
  };

  static const Map<int, Color> error = {
    10: Color(0xFF410002),
    20: Color(0xFF690005),
    30: Color(0xFF93000A),
    40: Color(0xFFBA1A1A),
    50: Color(0xFFDE3730),
    60: Color(0xFFFF5449),
    70: Color(0xFFFF897D),
    80: Color(0xFFFFB4AB),
    90: Color(0xFFFFDAD6),
    95: Color(0xFFFFEDEA),
  };
}

/// 构建完整 ColorScheme（亮色 / 暗色各一套）。
ColorScheme buildAppColorScheme(Brightness brightness) {
  const s = AppPalette.secondary;
  const t = AppPalette.tertiary;
  const n = AppPalette.neutral;
  const nv = AppPalette.neutralVariant;
  const e = AppPalette.error;

  return switch (brightness) {
    Brightness.light => ColorScheme(
      brightness: Brightness.light,
      primary: AppBrand.seed,
      onPrimary: Colors.white,
      primaryContainer: AppBrand.light,
      onPrimaryContainer: AppBrand.navy,
      primaryFixed: AppBrand.light,
      primaryFixedDim: AppBrand.fixedDim,
      onPrimaryFixed: AppBrand.navy,
      onPrimaryFixedVariant: AppBrand.seed,
      secondary: s[40]!,
      onSecondary: Colors.white,
      secondaryContainer: s[90]!,
      onSecondaryContainer: s[10]!,
      secondaryFixed: s[90]!,
      secondaryFixedDim: s[80]!,
      onSecondaryFixed: s[10]!,
      onSecondaryFixedVariant: s[30]!,
      tertiary: t[40]!,
      onTertiary: Colors.white,
      tertiaryContainer: t[90]!,
      onTertiaryContainer: t[10]!,
      tertiaryFixed: t[90]!,
      tertiaryFixedDim: t[80]!,
      onTertiaryFixed: t[10]!,
      onTertiaryFixedVariant: t[30]!,
      error: e[40]!,
      onError: Colors.white,
      errorContainer: e[90]!,
      onErrorContainer: e[10]!,
      surface: n[97]!,
      onSurface: n[10]!,
      surfaceDim: n[87]!,
      surfaceBright: n[100]!,
      surfaceContainerLowest: n[100]!,
      surfaceContainerLow: n[96]!,
      surfaceContainer: n[94]!,
      surfaceContainerHigh: n[92]!,
      surfaceContainerHighest: n[90]!,
      onSurfaceVariant: nv[30]!,
      outline: nv[50]!,
      outlineVariant: nv[80]!,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: n[20]!,
      onInverseSurface: n[95]!,
      inversePrimary: AppBrand.darkPrimary,
      surfaceTint: Colors.transparent,
    ),
    Brightness.dark => ColorScheme(
      brightness: Brightness.dark,
      primary: AppBrand.darkPrimary,
      onPrimary: const Color(0xFF00315F),
      primaryContainer: AppBrand.seed,
      onPrimaryContainer: AppBrand.light,
      primaryFixed: AppBrand.light,
      primaryFixedDim: AppBrand.fixedDim,
      onPrimaryFixed: AppBrand.navy,
      onPrimaryFixedVariant: AppBrand.seed,
      secondary: s[80]!,
      onSecondary: s[20]!,
      secondaryContainer: s[30]!,
      onSecondaryContainer: s[90]!,
      secondaryFixed: s[90]!,
      secondaryFixedDim: s[80]!,
      onSecondaryFixed: s[10]!,
      onSecondaryFixedVariant: s[30]!,
      tertiary: t[80]!,
      onTertiary: t[20]!,
      tertiaryContainer: t[30]!,
      onTertiaryContainer: t[90]!,
      tertiaryFixed: t[90]!,
      tertiaryFixedDim: t[80]!,
      onTertiaryFixed: t[10]!,
      onTertiaryFixedVariant: t[30]!,
      error: e[80]!,
      onError: e[20]!,
      errorContainer: e[30]!,
      onErrorContainer: e[90]!,
      surface: n[9]!,
      onSurface: n[90]!,
      surfaceDim: n[6]!,
      surfaceBright: n[24]!,
      surfaceContainerLowest: n[4]!,
      surfaceContainerLow: n[12]!,
      surfaceContainer: n[16]!,
      surfaceContainerHigh: n[20]!,
      surfaceContainerHighest: n[24]!,
      onSurfaceVariant: nv[80]!,
      outline: nv[60]!,
      outlineVariant: nv[30]!,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: n[90]!,
      onInverseSurface: n[20]!,
      inversePrimary: AppBrand.seed,
      surfaceTint: Colors.transparent,
    ),
  };
}

/// 优先使用平台提供的动态色板，否则回退到品牌色板。
///
/// 动态色板必须与当前主题亮度匹配，避免把亮色方案误用到深色主题，
/// 或在平台仅提供单侧色板时破坏另一侧主题。
ColorScheme resolveAppColorScheme(
  Brightness brightness, {
  ColorScheme? dynamicScheme,
}) {
  if (dynamicScheme?.brightness == brightness) {
    return dynamicScheme!;
  }
  return buildAppColorScheme(brightness);
}

/// 语义状态色（随明暗主题切换）。
///
/// 统一替代业务页中散落的成功 / 信息 / 提醒 / 危险硬编码色。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
  });

  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF1B7A3D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFE3F5E8),
    onSuccessContainer: Color(0xFF0B3B17),
    info: Color(0xFF1D5FA8),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE2EEFB),
    onInfoContainer: Color(0xFF0B2E57),
    warning: Color(0xFF9A5B13),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFF1DE),
    onWarningContainer: Color(0xFF3B2200),
    danger: Color(0xFFB3261E),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFBE4E2),
    onDangerContainer: Color(0xFF5C120E),
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF80DA92),
    onSuccess: Color(0xFF003917),
    successContainer: Color(0xFF003917),
    onSuccessContainer: Color(0xFF9BF7AC),
    info: Color(0xFFA6C8FF),
    onInfo: Color(0xFF00315F),
    infoContainer: Color(0xFF00315F),
    onInfoContainer: Color(0xFFD5E3FF),
    warning: Color(0xFFFFB875),
    onWarning: Color(0xFF4B2800),
    warningContainer: Color(0xFF4B2800),
    onWarningContainer: Color(0xFFFFDCC0),
    danger: Color(0xFFFFB4AA),
    onDanger: Color(0xFF690003),
    dangerContainer: Color(0xFF690003),
    onDangerContainer: Color(0xFFFFDAD5),
  );

  /// 按明暗模式取语义色。
  static AppSemanticColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 从当前主题取语义色（未注册时回退亮色）。
  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ?? light;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer:
          Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
    );
  }
}

/// 品牌渐变。
abstract final class AppGradient {
  /// 主操作 / 头像渐变。
  static const List<Color> primary = [Color(0xFF0A5CAD), Color(0xFF4E90DE)];

  /// 氛围渐变（深蓝到浅蓝）。
  static const List<Color> ambient = [Color(0xFF0A5CAD), Color(0xFFA9C7F2)];
}

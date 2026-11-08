/// MyCHU 玻璃材质系统。
///
/// 颜色、排版与尺寸沿用 Material 3；按压形变、辉光与折射由库原生组件提供。
/// 参数集中在这里，任何新的玻璃表面都走
/// [AppGlassMaterial.settingsFor] 与 [AppGlassMaterial.quality]，不在页面里重复调参。
///
/// 独立按钮和悬浮底栏使用 premium 折射；贴边顶底栏使用背景模糊与染色。
/// 地图按钮使用完整管线并叠加遮光底色，以保持图标对比度。
/// 着色器在本地协议同意后、构建根页面前由宿主预载。
library;

import "package:flutter/material.dart";
import "package:liquid_glass_widgets/liquid_glass_widgets.dart";

/// 玻璃材质的唯一来源。
abstract final class AppGlassMaterial {
  /// 完整折射、高光和色散；平台不支持时由库选择兼容路径。
  static const GlassQuality quality = GlassQuality.premium;

  /// 着色器未能采样背景时使用的兜底色透明度。
  static const double _fallbackAlpha = 0.94;

  /// 顶底栏的磨砂强度，与按钮透镜独立。
  static const double backgroundBlur = 16;

  static const double _thickness = 24;
  static const double _buttonBlur = 2;
  static const double _lightIntensity = 0.85;
  static const double _glowIntensity = 1;

  /// Passive bars use blur and tint only; keep button optics independent.
  static Color backgroundTintFor(
    ColorScheme colors, {
    bool platformViewBackdrop = false,
  }) => colors.surface.withValues(alpha: platformViewBackdrop ? .62 : .52);

  /// 按当前 M3 色板生成一份玻璃参数。
  ///
  /// 颜色只取 [ColorScheme.surface] 的明暗表面色阶。
  static LiquidGlassSettings settingsFor(
    ColorScheme colorScheme, {
    bool mapBackdrop = false,
  }) {
    final surface = colorScheme.surface;
    return LiquidGlassSettings(
      thickness: _thickness,
      blur: _buttonBlur,
      glassColor: surface.withValues(alpha: .16),
      backerColor: mapBackdrop ? surface.withValues(alpha: .45) : null,
      refractiveIndex: 1.24,
      lensModel: GlassLensModel.paraxial,
      chromaticAberration: .02,
      lightIntensity: _lightIntensity,
      glowIntensity: _glowIntensity,
      platformViewFallbackColor: surface.withValues(alpha: _fallbackAlpha),
    );
  }
}

import 'dart:ui' show ImageFilter;
import "package:flutter/material.dart";
import "package:liquid_glass_widgets/liquid_glass_widgets.dart";

import "../theme/app_glass.dart";

/// Background-only frosted material, with no refraction, rim or specular strokes.
/// Interactive controls use AppGlassButton for the full liquid effect.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.shape,
    required this.child,
    this.platformViewBackdrop = false,
    this.bottomFadeExtent = 0,
  });

  /// 玻璃轮廓，例如 `LiquidOval()` 或 `LiquidRoundedSuperellipse`。
  final LiquidShape shape;

  /// 叠在玻璃之上的内容。
  final Widget child;

  /// 地图平台视图使用更深的染色，确保浅色地图上的前景对比度。
  final bool platformViewBackdrop;

  /// Extends only the material below a fixed header, without moving its content.
  final double bottomFadeExtent;

  @override
  Widget build(BuildContext context) {
    final tint = AppGlassMaterial.backgroundTintFor(
      Theme.of(context).colorScheme,
      platformViewBackdrop: platformViewBackdrop,
    );
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: -bottomFadeExtent,
          child: IgnorePointer(
            child:
                bottomFadeExtent > 0
                    ? Stack(
                      fit: StackFit.expand,
                      children: [
                        const ProgressiveBlur(
                          maxSigma: AppGlassMaterial.backgroundBlur,
                        ),
                        LayoutBuilder(
                          builder:
                              (context, constraints) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      tint,
                                      tint,
                                      tint.withValues(alpha: 0),
                                    ],
                                    stops: [
                                      0,
                                      ((constraints.maxHeight -
                                                  bottomFadeExtent) /
                                              constraints.maxHeight)
                                          .clamp(0.0, 1.0),
                                      1,
                                    ],
                                  ),
                                ),
                              ),
                        ),
                      ],
                    )
                    : ClipPath(
                      clipper: ShapeBorderClipper(
                        shape: shape.toOutlinedBorder(),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: AppGlassMaterial.backgroundBlur,
                          sigmaY: AppGlassMaterial.backgroundBlur,
                        ),
                        child: ColoredBox(color: tint),
                      ),
                    ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Project settings and semantics around the library's native liquid button.
class AppGlassButton extends StatelessWidget {
  const AppGlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
    this.width,
    this.height = 44,
    this.shape = const LiquidRoundedRectangle(borderRadius: 22),
    this.mapBackdrop = false,
    this.transparent = false,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final String tooltip;
  final double? width;
  final double height;
  final LiquidShape shape;

  /// 地图上的按钮增加遮光底色，着色器不可用时回退为实时磨砂。
  final bool mapBackdrop;
  final bool transparent;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GlassButton.custom(
      onTap: onPressed ?? () {},
      enabled: onPressed != null,
      label: tooltip,
      width: width,
      height: height,
      shape: shape,
      // Disabled opacity layers cannot capture the refractive backdrop.
      quality: onPressed == null ? GlassQuality.minimal : AppGlassMaterial.quality,
      useOwnLayer: true,
      platformViewBackdrop: mapBackdrop && !ImageFilter.isShaderFilterSupported,
      settings: AppGlassMaterial.settingsFor(
        Theme.of(context).colorScheme,
        mapBackdrop: mapBackdrop,
      ),
      style:
          transparent ? GlassButtonStyle.transparent : GlassButtonStyle.filled,
      child: IconTheme.merge(
        data: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        child: child,
      ),
    ),
  );
}

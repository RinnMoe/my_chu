import 'package:flutter/material.dart';

/// 把 MyCHU 当前 Material 3 色板转换成 chat-demo 的 CSS 变量。
///
/// chat-demo 使用 `--dsw-*` 语义变量；这里只在 `body` 上覆盖语义层，
/// 不修改其布局、字体和组件结构。`!important` 用于压过聊天页自身的
/// `body[data-ds-dark-theme]` 声明。
String buildChatDemoThemeCss(ColorScheme colors) {
  String hex(Color color) {
    final argb = color.toARGB32();
    final alpha = (argb >> 24) & 0xff;
    final red = (argb >> 16) & 0xff;
    final green = (argb >> 8) & 0xff;
    final blue = argb & 0xff;
    if (alpha == 0xff) {
      return '#${red.toRadixString(16).padLeft(2, '0')}'
          '${green.toRadixString(16).padLeft(2, '0')}'
          '${blue.toRadixString(16).padLeft(2, '0')}';
    }
    return 'rgba($red, $green, $blue, ${(alpha / 255).toStringAsFixed(3)})';
  }

  String alpha(Color color, double opacity) =>
      hex(color.withValues(alpha: opacity));

  final values = <String, String>{
    '--dsw-alias-bg-base': hex(colors.surface),
    '--dsw-alias-bg-layer-2': hex(colors.surfaceContainerLow),
    '--dsw-alias-bg-layer-3': hex(colors.surfaceContainer),
    '--dsw-alias-bg-skeleton': alpha(colors.onSurface, 0.06),
    '--dsw-alias-border-inverted': alpha(colors.onSurface, 0.06),
    '--dsw-alias-border-l1': alpha(colors.outlineVariant, 0.45),
    '--dsw-alias-border-l2-darkmode-thin': alpha(colors.outlineVariant, 0.55),
    '--dsw-alias-border-l2': alpha(colors.outlineVariant, 0.8),
    '--dsw-alias-border-l3': hex(colors.outlineVariant),
    '--dsw-alias-brand-primary-invert': hex(colors.onPrimary),
    '--dsw-alias-brand-primary': hex(colors.primary),
    '--dsw-alias-brand-text': hex(colors.primary),
    '--dsw-alias-button-contrast-fill': hex(colors.primary),
    '--dsw-alias-button-elevated-fill': hex(colors.surfaceContainerHigh),
    '--dsw-alias-button-ghost-active-border': hex(colors.primary),
    '--dsw-alias-button-ghost-active-fill': hex(colors.primaryContainer),
    '--dsw-alias-button-ghost-active-hover': hex(colors.primaryContainer),
    '--dsw-alias-button-info-hover': hex(colors.primaryContainer),
    '--dsw-alias-button-primary-fill': hex(colors.primary),
    '--dsw-alias-button-primary-hover': hex(colors.primary),
    '--dsw-alias-interactive-bg-active': alpha(colors.onSurface, 0.12),
    '--dsw-alias-interactive-bg-hover-danger': alpha(colors.error, 0.08),
    '--dsw-alias-interactive-bg-hover': alpha(colors.onSurface, 0.06),
    '--dsw-alias-interactive-bg-hover-accent': alpha(colors.onSurface, 0.12),
    '--dsw-alias-label-caption': hex(colors.onSurfaceVariant),
    '--dsw-alias-label-dimmed': hex(colors.outline),
    '--dsw-alias-label-primary-foreground': hex(colors.onPrimary),
    '--dsw-alias-label-primary-inverted': hex(colors.onPrimary),
    '--dsw-alias-label-primary': hex(colors.onSurface),
    '--dsw-alias-label-secondary': hex(colors.onSurfaceVariant),
    '--dsw-alias-label-tertiary': hex(colors.onSurfaceVariant),
    '--dsw-alias-markdown-citation': hex(colors.surfaceContainerHigh),
    '--dsw-alias-markdown-code-block-banner': hex(colors.surfaceContainerHigh),
    '--dsw-alias-markdown-code-block': hex(colors.surfaceContainerHigh),
    '--dsw-alias-markdown-inline-code': hex(colors.surfaceContainerHighest),
    '--dsw-alias-markdown-placeholder': hex(colors.surfaceContainerHighest),
    '--dsw-alias-markdown-tag': hex(colors.surfaceContainerHighest),
    '--dsw-alias-state-error-primary': hex(colors.error),
    '--dsw-alias-state-error-secondary': hex(colors.error),
    '--dsw-alias-toast-bg': hex(colors.inverseSurface),
    '--dsw-alias-tooltip-bg': hex(colors.inverseSurface),
    '--md-sys-color-on-primary-container': hex(colors.onPrimaryContainer),
    '--md-sys-color-on-secondary-container': hex(colors.onSecondaryContainer),
    '--dsw-specific-bubble': hex(colors.primaryContainer),
    '--dsw-specific-bubble-foreground': hex(colors.onPrimaryContainer),
    // 亮色输入区比默认 surfaceContainerHigh 更浅；深色保持高一层以拉开背景。
    '--dsw-specific-input-major': hex(
      colors.brightness == Brightness.light
          ? colors.surfaceContainer
          : colors.surfaceContainerHigh,
    ),
    '--dsw-specific-login-input': hex(colors.surfaceContainerHigh),
    '--dsw-specific-menu': hex(colors.surfaceContainerHigh),
    '--dsw-specific-selector': hex(colors.surfaceContainerHigh),
    '--dsw-specific-sidebar-fill': hex(colors.surfaceContainerLow),
    '--dsw-specific-sidebar-nav-item-active-accent': hex(
      colors.secondaryContainer,
    ),
    '--dsw-specific-sidebar-nav-item-active-foreground': hex(
      colors.onSecondaryContainer,
    ),
    '--dsw-specific-sidebar-nav-item-hover': hex(colors.surfaceContainerHigh),
  };

  final declarations = values.entries
      .map((entry) => '  ${entry.key}: ${entry.value} !important;')
      .join('\n');
  return 'body, body[data-ds-dark-theme] {\n$declarations\n}\n';
}

import 'package:flutter/widgets.dart';

import 'development_mode_service.dart';

enum ViewportOrientation { portrait, landscape }

/// Safe-area presets used by the development viewport preview.
enum ViewportSafeAreaTemplate {
  none(label: '无安全区', portrait: EdgeInsets.zero, landscape: EdgeInsets.zero),
  iphone(
    label: 'iPhone 安全区',
    portrait: EdgeInsets.fromLTRB(0, 47, 0, 34),
    landscape: EdgeInsets.fromLTRB(47, 0, 47, 21),
  ),
  statusBar(
    label: '仅状态栏',
    portrait: EdgeInsets.fromLTRB(0, 20, 0, 0),
    landscape: EdgeInsets.zero,
  ),
  homeIndicator(
    label: '仅 Home Indicator',
    portrait: EdgeInsets.fromLTRB(0, 0, 0, 34),
    landscape: EdgeInsets.fromLTRB(0, 0, 0, 21),
  );

  final String label;
  final EdgeInsets portrait;
  final EdgeInsets landscape;

  const ViewportSafeAreaTemplate({
    required this.label,
    required this.portrait,
    required this.landscape,
  });

  EdgeInsets inOrientation(ViewportOrientation orientation) {
    return orientation == ViewportOrientation.portrait ? portrait : landscape;
  }
}

@immutable
class ViewportPreviewPreset {
  final String id;
  final String label;
  final double width;
  final double height;

  const ViewportPreviewPreset({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
  });
}

@immutable
class ViewportPreviewConfig {
  static const minWidth = 320.0;
  static const maxWidth = 500.0;
  static const minHeight = 568.0;
  static const maxHeight = 1000.0;

  final double portraitWidth;
  final double portraitHeight;
  final ViewportOrientation orientation;
  final ViewportSafeAreaTemplate safeAreaTemplate;

  const ViewportPreviewConfig({
    required this.portraitWidth,
    required this.portraitHeight,
    this.orientation = ViewportOrientation.portrait,
    this.safeAreaTemplate = ViewportSafeAreaTemplate.iphone,
  });

  double get width =>
      orientation == ViewportOrientation.portrait
          ? portraitWidth
          : portraitHeight;

  double get height =>
      orientation == ViewportOrientation.portrait
          ? portraitHeight
          : portraitWidth;

  Size get size => Size(width, height);

  EdgeInsets get safeArea => safeAreaTemplate.inOrientation(orientation);

  ViewportPreviewConfig copyWith({
    double? portraitWidth,
    double? portraitHeight,
    ViewportOrientation? orientation,
    ViewportSafeAreaTemplate? safeAreaTemplate,
  }) {
    return ViewportPreviewConfig(
      portraitWidth: portraitWidth ?? this.portraitWidth,
      portraitHeight: portraitHeight ?? this.portraitHeight,
      orientation: orientation ?? this.orientation,
      safeAreaTemplate: safeAreaTemplate ?? this.safeAreaTemplate,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ViewportPreviewConfig &&
        other.portraitWidth == portraitWidth &&
        other.portraitHeight == portraitHeight &&
        other.orientation == orientation &&
        other.safeAreaTemplate == safeAreaTemplate;
  }

  @override
  int get hashCode =>
      Object.hash(portraitWidth, portraitHeight, orientation, safeAreaTemplate);
}

/// Process-local DEV state for the full-app iPhone viewport preview.
///
/// It deliberately has no persistence. Leaving the app or restarting it
/// always restores the real device window.
class ViewportPreviewService {
  static const presets = <ViewportPreviewPreset>[
    ViewportPreviewPreset(
      id: 'iphone-se',
      label: 'iPhone SE · 375 × 667',
      width: 375,
      height: 667,
    ),
    ViewportPreviewPreset(
      id: 'iphone-15',
      label: 'iPhone · 390 × 844',
      width: 390,
      height: 844,
    ),
    ViewportPreviewPreset(
      id: 'iphone-pro-max',
      label: 'iPhone Pro Max · 430 × 932',
      width: 430,
      height: 932,
    ),
  ];

  static final ValueNotifier<ViewportPreviewConfig?> config =
      ValueNotifier<ViewportPreviewConfig?>(null);

  static bool get isEnabled => config.value != null;

  static void enable({ViewportPreviewConfig? value}) {
    if (!DevelopmentModeService.isDev) return;
    config.value = value ?? fromPreset('iphone-15');
  }

  static void enablePreset(String id) {
    if (!DevelopmentModeService.isDev) return;
    config.value = fromPreset(id);
  }

  static void disable() {
    config.value = null;
  }

  static void setCustom({
    required double width,
    required double height,
    ViewportOrientation orientation = ViewportOrientation.portrait,
    ViewportSafeAreaTemplate safeAreaTemplate = ViewportSafeAreaTemplate.iphone,
  }) {
    _validateSize(width: width, height: height);
    if (!DevelopmentModeService.isDev) return;
    config.value = ViewportPreviewConfig(
      portraitWidth: width,
      portraitHeight: height,
      orientation: orientation,
      safeAreaTemplate: safeAreaTemplate,
    );
  }

  static void setOrientation(ViewportOrientation orientation) {
    final current = config.value;
    if (current == null || !DevelopmentModeService.isDev) return;
    config.value = current.copyWith(orientation: orientation);
  }

  static void setSafeAreaTemplate(ViewportSafeAreaTemplate template) {
    final current = config.value;
    if (current == null || !DevelopmentModeService.isDev) return;
    config.value = current.copyWith(safeAreaTemplate: template);
  }

  static ViewportPreviewConfig fromPreset(String id) {
    final preset = presets.firstWhere(
      (item) => item.id == id,
      orElse: () => presets[1],
    );
    return ViewportPreviewConfig(
      portraitWidth: preset.width,
      portraitHeight: preset.height,
    );
  }

  static void _validateSize({required double width, required double height}) {
    if (!width.isFinite ||
        width < ViewportPreviewConfig.minWidth ||
        width > ViewportPreviewConfig.maxWidth) {
      throw RangeError(
        'width must be between ${ViewportPreviewConfig.minWidth} and '
        '${ViewportPreviewConfig.maxWidth}',
      );
    }
    if (!height.isFinite ||
        height < ViewportPreviewConfig.minHeight ||
        height > ViewportPreviewConfig.maxHeight) {
      throw RangeError(
        'height must be between ${ViewportPreviewConfig.minHeight} and '
        '${ViewportPreviewConfig.maxHeight}',
      );
    }
  }

  @visibleForTesting
  static void debugReset() {
    config.value = null;
  }
}

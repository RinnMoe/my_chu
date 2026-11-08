import "dart:math" as math;

import "package:flutter/material.dart";
import "package:liquid_glass_widgets/liquid_glass_widgets.dart";

import "../../../widgets/glass_surface.dart";

/// 地图页顶部的玻璃搜索 chrome。
///
/// 收起状态是右上角一个与地图操作按钮同尺寸的玻璃圆形放大镜；点击后原地长成
/// 胶囊搜索栏：宽度和高度同时形变，内容在形变后半程淡入，两端始终保持半圆，
/// 不是把圆形横向拉长。形变结束后自动聚焦输入框并唤起输入法，提交或点关闭按钮
/// 收起。按钮通过 `mapBackdrop` 使用折射材质与遮光底色；
/// 玻璃只提供材质，图标、输入与焦点仍按 M3 角色决定。
class MapboxMapChrome extends StatefulWidget {
  const MapboxMapChrome({
    super.key,
    required this.asRootTab,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearch,
  });

  /// 返回按钮与搜索栏之间的间距。
  static const double gap = 8;

  /// 收起状态的圆形放大镜尺寸，与地图右侧操作按钮一致。
  static const double buttonSize = 44;

  /// 展开/收起形变时长。
  static const Duration expandDuration = Duration(milliseconds: 240);

  static const double _minExpandedHeight = 56;

  final bool asRootTab;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearch;

  /// chrome 槽高（不含 SafeArea 与外部 padding）：取展开后的胶囊高度，随系统
  /// 字体缩放增高；收起态圆钮在槽内垂直居中，形变时不会挤压右侧控件。
  static double heightFor(BuildContext context) {
    final lineHeight = MediaQuery.textScalerOf(context).scale(16) * 1.5;
    return math.max(_minExpandedHeight, lineHeight + 20);
  }

  @override
  State<MapboxMapChrome> createState() => _MapboxMapChromeState();
}

class _MapboxMapChromeState extends State<MapboxMapChrome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph;
  late final Animation<double> _morphCurve;
  late final Animation<double> _collapsedOpacity;
  late final Animation<double> _expandedOpacity;

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      vsync: this,
      duration: MapboxMapChrome.expandDuration,
    );
    _morphCurve = CurvedAnimation(parent: _morph, curve: Curves.easeOutCubic);
    _collapsedOpacity = CurvedAnimation(
      parent: _morph,
      curve: const Interval(0, 0.25, curve: Curves.easeIn),
    );
    _expandedOpacity = CurvedAnimation(
      parent: _morph,
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  void _expand() {
    if (_expanded) return;
    setState(() => _expanded = true);
    // 形变结束后再聚焦：输入框和键盘不会和形变抢时间。
    _morph.forward().whenComplete(() {
      if (!mounted || !_expanded) return;
      widget.searchFocusNode.requestFocus();
    });
  }

  void _collapse() {
    widget.searchFocusNode.unfocus();
    if (!_expanded) return;
    setState(() => _expanded = false);
    _morph.reverse();
  }

  void _submit(String text) {
    widget.onSearch(text);
    _collapse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chromeHeight = MapboxMapChrome.heightFor(context);
    return SizedBox(
      height: chromeHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final back = widget.asRootTab ? null : _buildBackButton(context);
          final reserved =
              back == null
                  ? 0.0
                  : MapboxMapChrome.buttonSize + MapboxMapChrome.gap;
          final available = math.max(0.0, constraints.maxWidth - reserved);
          return Row(
            children: [
              if (back != null) ...[
                back,
                const SizedBox(width: MapboxMapChrome.gap),
              ],
              Expanded(
                child: AnimatedBuilder(
                  animation: _morph,
                  builder: (context, _) {
                    final progress = _morphCurve.value;
                    final width = _lerp(
                      MapboxMapChrome.buttonSize,
                      available,
                      progress,
                    ).clamp(0.0, available);
                    final height = _lerp(
                      MapboxMapChrome.buttonSize,
                      chromeHeight,
                      progress,
                    );
                    return Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: _buildSearchSurface(
                          theme,
                          height: height,
                          availableWidth: available,
                          expandedHeight: chromeHeight,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static double _lerp(double from, double to, double t) =>
      from + (to - from) * t;

  Widget _buildBackButton(BuildContext context) => AppGlassButton(
    width: MapboxMapChrome.buttonSize,
    height: MapboxMapChrome.buttonSize,
    shape: const LiquidOval(),
    mapBackdrop: true,
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: () => Navigator.maybePop(context),
    child: const Icon(Icons.arrow_back),
  );

  Widget _buildSearchSurface(
    ThemeData theme, {
    required double height,
    required double availableWidth,
    required double expandedHeight,
  }) {
    // 圆角取当前高度的一半：收起是圆形，展开后是两端半圆的胶囊；不要用
    // LiquidOval，否则宽高不等时会被画成椭圆。
    final radius = height / 2;
    if (!_expanded && _morph.value == 0) return _buildCollapsed();
    return AppGlassSurface(
      shape: LiquidRoundedRectangle(borderRadius: radius),
      platformViewBackdrop: true,
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 展开内容按最终尺寸布局，靠形变容器裁出可见部分：宽度增长时内容
            // 是被“揭开”而不是被横向压扁。
            ClipRect(
              child: IgnorePointer(
                ignoring: !_expanded,
                child: FadeTransition(
                  opacity: _expandedOpacity,
                  child: OverflowBox(
                    alignment: Alignment.centerRight,
                    minWidth: availableWidth,
                    maxWidth: availableWidth,
                    minHeight: expandedHeight,
                    maxHeight: expandedHeight,
                    child: SizedBox(
                      width: availableWidth,
                      height: expandedHeight,
                      child: _buildExpanded(theme, radius),
                    ),
                  ),
                ),
              ),
            ),
            if (!_expanded || _morph.value < 1)
              Align(
                alignment: Alignment.centerRight,
                child: IgnorePointer(
                  ignoring: _expanded,
                  child: FadeTransition(
                    opacity: ReverseAnimation(_collapsedOpacity),
                    child: _buildCollapsed(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsed() => AppGlassButton(
    key: const ValueKey("map-search-collapsed"),
    width: MapboxMapChrome.buttonSize,
    height: MapboxMapChrome.buttonSize,
    shape: const LiquidOval(),
    mapBackdrop: true,
    tooltip: "搜索地点",
    onPressed: _expand,
    transparent: _expanded || _morph.value > 0,
    child: const Icon(Icons.search),
  );

  Widget _buildExpanded(ThemeData theme, double radius) {
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurface,
    );
    return ListenableBuilder(
      key: const ValueKey("map-search-expanded"),
      listenable: widget.searchFocusNode,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              AppGlassButton(
                width: 40,
                height: 40,
                transparent: true,
                mapBackdrop: true,
                tooltip: "搜索",
                onPressed: () => _submit(widget.searchController.text),
                child: const Icon(Icons.search),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextField(
                    controller: widget.searchController,
                    focusNode: widget.searchFocusNode,
                    textInputAction: TextInputAction.search,
                    style: textStyle,
                    // 输入框只占位，不画自己的底色和边框：玻璃是唯一表面，
                    // 焦点由外圈描边表达。
                    decoration: InputDecoration(
                      hintText: "支持教室编号查询",
                      hintStyle: textStyle?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: _submit,
                  ),
                ),
              ),
              AppGlassButton(
                width: 40,
                height: 40,
                transparent: true,
                mapBackdrop: true,
                tooltip: "收起搜索",
                onPressed: _collapse,
                child: const Icon(Icons.close),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if (widget.searchFocusNode.hasFocus)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

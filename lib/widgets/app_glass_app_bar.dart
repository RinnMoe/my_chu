import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:liquid_glass_widgets/liquid_glass_widgets.dart";

import "glass_surface.dart";

/// 贴边直角玻璃标题栏。
///
/// 玻璃只做背景：标题、动作、系统状态栏样式与滚动行为仍由 [AppBar] 决定。
/// 页面用 `Scaffold(extendBodyBehindAppBar: true)` 让滚动内容穿到栏后；AppBar
/// 自身背景透明，才能看到玻璃与后面的内容。
class AppGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppGlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.titleSpacing,
    this.systemOverlayStyle,
    this.flexibleSpace,
    this.bottom,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final double? titleSpacing;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;

  AppBar _bar() => AppBar(
    title: title,
    actions: actions,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    centerTitle: centerTitle,
    titleSpacing: titleSpacing,
    systemOverlayStyle: systemOverlayStyle,
    flexibleSpace: flexibleSpace,
    bottom: bottom,
    // 玻璃是唯一表面：AppBar 不画底色、tint 或滚动阴影。
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    forceMaterialTransparency: true,
  );

  @override
  Size get preferredSize => _bar().preferredSize;

  @override
  Widget build(BuildContext context) => AppGlassSurface(
    shape: const LiquidRoundedRectangle(borderRadius: 0),
    bottomFadeExtent: 32,
    child: _bar(),
  );
}

import 'package:flutter/material.dart';

/// 通用加载占位块：与“应用”页加载占位同风格（surfaceContainerHigh 圆角块）。
///
/// 数据加载完成前用若干 [SkeletonBlock] 拼出占位布局，避免内容在加载成功前
/// 直接消失或跳动；加载完成后替换为真实内容即可。
class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double? height;
  final double? radius;
  final Color? color;

  const SkeletonBlock({
    super.key,
    this.width,
    this.height,
    this.radius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? (Theme.of(context).colorScheme.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(radius ?? 4),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// WebView 共享底栏：后退 / 前进 / 刷新 / UA 切换（图标式，无文字）。
///
/// 认证 WebView 与手动登录 WebView 共用，是否显示由页面级 `showBottomBar`
/// 控制（默认显示；评教系统等应用可关闭）。
class WebViewBottomBar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final bool useDesktopUA;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onToggleUA;

  const WebViewBottomBar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.useDesktopUA,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onToggleUA,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: '后退',
              onPressed: canGoBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_outlined),
            ),
            IconButton(
              tooltip: '前进',
              onPressed: canGoForward ? onForward : null,
              icon: const Icon(Icons.arrow_forward_outlined),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: onReload,
              icon: const Icon(Icons.refresh_outlined),
            ),
            IconButton(
              tooltip: useDesktopUA ? '切换为移动版' : '切换为桌面版',
              onPressed: onToggleUA,
              icon: Icon(
                useDesktopUA
                    ? Icons.desktop_windows_outlined
                    : Icons.smartphone_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

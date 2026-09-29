/// SDK-independent external navigation capability shared by campus features.
///
/// 不接入地图 SDK；仅通过 URI 调起高德、百度或系统地图：
/// 高德用 GCJ-02，百度用 BD-09（coord_type=bd09ll），系统地图用 WGS84。
/// 尝试顺序：所选应用 → 其他已安装地图 → 系统地图；全部失败时由入口提示复制坐标。
library;

import "package:flutter/foundation.dart"
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";

import "coordinate_converter.dart";

export "coordinate_converter.dart";
export "navigation_target_resolver.dart";

/// 外部地图应用。
enum ExternalMapApp { amap, baidu, system }

/// 外部地图应用展示信息。
class ExternalMapAppInfo {
  final ExternalMapApp app;
  final String label;
  final IconData icon;

  const ExternalMapAppInfo({
    required this.app,
    required this.label,
    required this.icon,
  });
}

/// 外部地图应用清单。
const List<ExternalMapAppInfo> externalMapApps = [
  ExternalMapAppInfo(
    app: ExternalMapApp.amap,
    label: "高德地图",
    icon: Icons.navigation,
  ),
  ExternalMapAppInfo(app: ExternalMapApp.baidu, label: "百度地图", icon: Icons.map),
  ExternalMapAppInfo(
    app: ExternalMapApp.system,
    label: "系统地图",
    icon: Icons.public,
  ),
];

/// 外部导航目标（WGS84 权威坐标 + 展示名；入口坐标已核验才可导航）。
class ExternalNavigationTarget {
  final String name;
  final NavCoordinate wgs84;
  final String? entranceLabel;

  const ExternalNavigationTarget({
    required this.name,
    required this.wgs84,
    this.entranceLabel,
  });
}

/// 外部导航 URI 构造（纯函数，可单测）。
class ExternalNavigationUri {
  const ExternalNavigationUri();

  static const CoordinateConverter _converter = CoordinateConverter();
  static const String _androidBaiduSource = "andr.rinn.mychu";
  static const String _iosBaiduSource = "ios.rinn.mychu";

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 按目标地图生成 URI；不支持的组合返回 null。
  Uri? build(ExternalMapApp app, ExternalNavigationTarget target) {
    if (!target.wgs84.isValid || target.wgs84.isOrigin) return null;
    switch (app) {
      case ExternalMapApp.amap:
        final gcj = _converter.wgs84ToGcj02(target.wgs84);
        return Uri.parse(
          "${_isIOS ? 'iosamap' : 'androidamap'}://navi?sourceApplication=mychu"
          "&lat=${gcj.latitude}&lon=${gcj.longitude}"
          "&poiname=${Uri.encodeComponent(_label(target))}"
          "&style=2&dev=0",
        );
      case ExternalMapApp.baidu:
        final bd = _converter.wgs84ToBd09(target.wgs84);
        return Uri.parse(
          "baidumap://map/direction"
          "?destination=latlng:${bd.latitude},${bd.longitude}"
          "|name:${Uri.encodeComponent(_label(target))}"
          "&coord_type=bd09ll&mode=walking"
          "&src=${_isIOS ? _iosBaiduSource : _androidBaiduSource}",
        );
      case ExternalMapApp.system:
        if (_isIOS) {
          return Uri.https("maps.apple.com", "/", {
            "ll": "${target.wgs84.latitude},${target.wgs84.longitude}",
            "q": _label(target),
          });
        }
        return Uri.parse(
          "geo:${target.wgs84.latitude},${target.wgs84.longitude}"
          "?q=${Uri.encodeComponent(_label(target))}",
        );
    }
  }

  static String _label(ExternalNavigationTarget target) =>
      target.entranceLabel != null && target.entranceLabel!.isNotEmpty
          ? target.entranceLabel!
          : target.name;
}

/// 外部导航能力：安装检测、调起、降级链、选择面板。
class ExternalNavigationCapability {
  /// 可注入的 URI 可用性检测（默认 url_launcher）。
  final Future<bool> Function(Uri uri) canOpen;

  /// 可注入的 URI 调起（默认 url_launcher）。
  final Future<bool> Function(Uri uri) open;

  ExternalNavigationCapability({
    Future<bool> Function(Uri uri)? canOpen,
    Future<bool> Function(Uri uri)? open,
  }) : canOpen = canOpen ?? _defaultCanOpen,
       open = open ?? _defaultOpen;

  static Future<bool> _defaultCanOpen(Uri uri) => canLaunchUrl(uri);
  static Future<bool> _defaultOpen(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// 当前已安装/可调起的外部地图。
  Future<List<ExternalMapApp>> availableApps() async {
    final result = <ExternalMapApp>[];
    for (final info in externalMapApps) {
      final uri = const ExternalNavigationUri().build(info.app, _probeTarget);
      if (uri == null) continue;
      if (await canOpen(uri)) result.add(info.app);
    }
    return result;
  }

  Future<bool> _launch(
    ExternalMapApp app,
    ExternalNavigationTarget target,
  ) async {
    final uri = const ExternalNavigationUri().build(app, target);
    if (uri == null || !await canOpen(uri)) return false;
    return open(uri);
  }

  Future<bool> _launchWithFeedback(
    BuildContext context,

    ExternalMapApp app,
    ExternalNavigationTarget target,
  ) async {
    final launched = await launchWithFallback(app, target);
    if (launched || !context.mounted) return launched;

    const message = '无法打开地图。请重新打开导航面板并选择“复制坐标”获取 WGS84 坐标。';
    {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text(message)));
    }
    return false;
  }

  /// 尝试所选应用、其他已安装地图和系统地图；全部失败返回 false。
  Future<bool> launchWithFallback(
    ExternalMapApp preferred,
    ExternalNavigationTarget target,
  ) async {
    final ordered = <ExternalMapApp>[
      preferred,
      ...externalMapApps.map((i) => i.app).where((a) => a != preferred),
    ];
    for (final app in ordered) {
      if (await _launch(app, target)) return true;
    }
    return false;
  }

  /// 显示外部地图选择面板；返回是否成功调起。
  Future<bool> showSheet(
    BuildContext context,
    ExternalNavigationTarget target,
  ) async {
    if (!target.wgs84.isValid || target.wgs84.isOrigin) return false;
    final apps = await availableApps();
    if (!context.mounted) return false;

    final selected = await showModalBottomSheet<ExternalMapApp>(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "导航至：${target.name}",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final info in externalMapApps)
                  if (apps.contains(info.app))
                    ListTile(
                      leading: Icon(info.icon),
                      title: Text(info.label),
                      onTap: () => Navigator.of(context).pop(info.app),
                    ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text("复制坐标"),
                  subtitle: Text(_formatCoordinate(target.wgs84)),
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: _formatCoordinate(target.wgs84)),
                    );
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        const SnackBar(content: Text("坐标已复制（WGS84）")),
                      );
                  },
                ),
              ],
            ),
          ),
    );
    if (selected == null) return false;
    if (!context.mounted) return false;
    return _launchWithFeedback(context, selected, target);
  }

  static const ExternalNavigationTarget _probeTarget = ExternalNavigationTarget(
    name: "MyCHU 导航探测",
    wgs84: NavCoordinate(longitude: 116.397, latitude: 39.908),
  );

  static String _formatCoordinate(NavCoordinate c) =>
      "${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)} (WGS84)";
}

/// 便捷入口：复制坐标文本到剪贴板。
Future<void> copyCoordinate(
  BuildContext context,
  NavCoordinate coordinate,
) async {
  final text =
      "${coordinate.latitude.toStringAsFixed(6)},"
      "${coordinate.longitude.toStringAsFixed(6)}";
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text("坐标已复制（WGS84）")));
}

# url_launcher_ohos

本项目基于 [url_launcher](https://pub.dev/packages/url_launcher) 开发。

## 简介

url_launcher_ohos 是 url_launcher 插件的 OpenHarmony 平台实现，用于在 OpenHarmony 应用中启动 URL。支持在系统浏览器或应用内 WebView 中打开网页链接，同时支持拨打电话、打开应用商店等系统功能。

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

```yaml
dependencies:
  url_launcher_ohos:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/url_launcher/url_launcher_ohos
      # ref: url_launcher_v6.3.2-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `url_launcher_v6.3.2-ohos-1.0.0` | `url_launcher_v6.3.2-ohos-1.0.1` | `br_url_launcher-v6.3.2_ohos` |
| 3.35 | `url_launcher_v6.3.2-ohos-1.0.0` | `url_launcher_v6.3.2-ohos-1.0.1` | `br_url_launcher-v6.3.2_ohos` |
| 3.27 | `url_launcher_v6.3.1-ohos-1.0.0` | `url_launcher_v6.3.1-ohos-1.0.1` | `br_url_launcher_v6.3.1_ohos` |
| 3.22 | `url_launcher_v6.3.0-ohos-1.0.0` | `url_launcher_v6.3.0-ohos-1.0.1` | `br_url_launcher-v6.3.0_ohos` |
| 3.7 | `url_launcher_v6.1.11-ohos-1.0.0` | `url_launcher_v6.1.11-ohos-1.0.1` | `master` |

## 约束与限制

### 兼容性

在以下版本中已测试通过：

1. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.1.0.117 SP6;
2. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.1.0.117 SP6;

### 权限要求

本插件需要以下权限：

**在 entry 目录下的 module.json5 中添加权限**

打开 `entry/src/main/module.json5`，添加：

```json
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"  // 请替换为您的应用实际入口 Ability 名称
      ],
      "when": "inuse"
    }
  }
]
```

**在 entry 目录下添加申请以上权限的原因**

打开 `entry/src/main/resources/base/element/string.json`，添加：

```json
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络访问网页"
    }
  ]
}
```

## 使用示例

以下示例展示了如何使用 url_launcher_ohos 在浏览器中打开网页链接：

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'URL Launcher Demo',
      home: const UrlLaunchDemo(),
    );
  }
}

class UrlLaunchDemo extends StatefulWidget {
  const UrlLaunchDemo({super.key});

  final String url = 'https://www.openharmony.cn';

  /// 在系统浏览器中打开 URL
  Future<void> _launchInBrowser(String url) async {
    final launcher = UrlLauncherPlatform.instance;
    final canLaunch = await launcher.canLaunch(url);

    // 检查Widget是否仍在树中
    if (!mounted) {
      return;
    }
    if (!canLaunch) {
      // 显示友好的提示信息而非抛出异常
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接: $url')),
      );
      return;
    }

    final launched = await launcher.launch(
      url,
      useSafariVC: false,
      useWebView: false,
      enableJavaScript: false,
      enableDomStorage: false,
      universalLinksOnly: false,
      headers: <String, String>{},
    );

    // 再次检查
    if (!mounted) {
      return;
    }

    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开链接失败: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('URL Launcher 示例'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _launchInBrowser(url),
          child: const Text('在浏览器中打开'),
        ),
      ),
    );
  }
}
```

## 使用说明

### 1. 在系统浏览器中打开 URL

使用 `launch` 方法，设置 `useWebView: false` 在系统浏览器中打开链接：

```dart
final launcher = UrlLauncherPlatform.instance;
await launcher.launch(
  'https://www.openharmony.cn',
  useSafariVC: false,
  useWebView: false,
  enableJavaScript: false,
  enableDomStorage: false,
  universalLinksOnly: false,
  headers: <String, String>{},
);
```

### 2. 在应用内 WebView 中打开 URL

设置 `useWebView: true` 在应用内 WebView 中打开链接：

```dart
await launcher.launch(
  'https://www.openharmony.cn',
  useSafariVC: true,
  useWebView: true,
  enableJavaScript: true,
  enableDomStorage: true,
  universalLinksOnly: false,
  headers: <String, String>{
    'harmony_browser_page': 'pages/LaunchInAppPage' // OHOS平台特有配置，指定应用内WebView页面路径
  },
);
```

### 3. 检查 URL 是否可启动

在启动 URL 前，可以使用 `canLaunch` 方法检查设备是否支持处理该 URL：

```dart
if (await launcher.canLaunch('https://www.openharmony.cn')) {
  await launcher.launch(
    'https://www.openharmony.cn',
    useSafariVC: false,
    useWebView: false,
    enableJavaScript: false,
    enableDomStorage: false,
    universalLinksOnly: false,
    headers: <String, String>{},
  );
}
```

### 4. 关闭 WebView

当使用 WebView 模式打开 URL 后，可以调用 `closeWebView` 方法关闭 WebView：

```dart
await launcher.closeWebView();
```

### 5. 拨打电话

使用 `tel:` 协议可以启动系统拨号界面：

```dart
final Uri launchUri = Uri(
  scheme: 'tel',
  path: '1234567890',
);
await launcher.launch(
  launchUri.toString(),
  useSafariVC: false,
  useWebView: false,
  enableJavaScript: false,
  enableDomStorage: false,
  universalLinksOnly: false,
  headers: <String, String>{},
);
```

### 6. 打开应用商店

使用 `store:` 协议可以打开应用商店：

```dart
const String url = '应用商店链接';
if (await launcher.canLaunch(url)) {
  await launcher.launchUrl(
    url,
    const LaunchOptions(mode: PreferredLaunchMode.externalApplication),
  );
}
```

## 接口说明

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

#### UrlLauncherPlatform

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
|------|------|----------|--------|---------------|------|
| canLaunch() | 方法 | String url | Future<bool> | yes | 检查设备是否可以启动一个特定的URL方案 |
| launch | 方法 | String url,<br/>required bool useSafariVC,<br/>required bool useWebView,<br/>required bool enableJavaScript,<br/>required bool enableDomStorage,<br/>required bool universalLinksOnly,<br/>required Map<String, String> headers,<br/>String? webOnlyWindowName | Future<bool> | yes | 指定跳转参数Url路径 |
| launchUrl() | 方法 | String url,<br/>[LaunchOptions](#LaunchOptions) options | Future<bool> | yes | 指定跳转浏览器并打开Url |
| closeWebView() | 方法 | / | Future<void> | yes | 关闭WebView页面 |

#### LaunchOptions

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
|------|------|----------|--------|---------------|------|
| mode | 属性 | / | [PreferredLaunchMode](#PreferredLaunchMode) | yes | 启动 URL 所需的模式 |
| webViewConfiguration | 属性 | / | [InAppWebViewConfiguration](#InAppWebViewConfiguration) | yes | 在 [PreferredLaunchMode.inAppWebView] 模式下配置 Web 视图 |
| webOnlyWindowName | 属性 | / | String? | yes | 取消设置时的默认行为应该是在新选项卡中打开 URL |

#### PreferredLaunchMode

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
|------|------|----------|--------|---------------|------|
| platformDefault | 枚举值 | / | enum | yes | 启动方式由平台决定 |
| inAppWebView | 枚举值 | / | enum | yes | 加载到inAppWebView |
| externalApplication | 枚举值 | / | enum | yes | 将 URL 传递给外部应用程序处理 |
| externalNonBrowserApplication | 枚举值 | / | enum | yes | 将 URL 传递给外部非浏览器应用程序处理 |

#### InAppWebViewConfiguration

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
|------|------|----------|--------|---------------|------|
| enableJavaScript | 属性 | / | bool | yes | 如果设置为true，则在WebView中启用JavaScript |
| enableDomStorage | 属性 | / | bool | yes | 当该值设置为true，WebView启用DOM存储 |
| headers | 属性 | / | Map<String, String> | yes | 在网页中打开Url时的请求头参数 |

#### launch 方法参数

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
|------|------|----------|--------|---------------|------|
| url | 参数 | String | / | yes | 跳转地址 |
| useSafariVC | 参数 | bool | / | yes | 是否在Safari视图控制器中打开URL |
| useWebView | 参数 | bool | / | yes | 如果设置为false，则在设备的默认浏览器中打开URL；否则，在WebView中启动URL |
| enableJavaScript | 参数 | bool | / | yes | 如果设置为true，则在WebView中启用JavaScript |
| enableDomStorage | 参数 | bool | / | yes | 当该值设置为true，WebView启用DOM存储 |
| universalLinksOnly | 参数 | bool | / | yes | 用于控制是否仅通过Universal Links打开网页 |
| headers | 参数 | Map<String, String> | / | yes | 在网页中打开Url时的请求头参数 |
| webOnlyWindowName | 参数 | String? | / | yes | 取消设置时的默认行为应该是在新选项卡中打开URL |

## 遗留问题

无

## 目录结构

```
flutter_packages/
└── packages/
    └── url_launcher/
        └── url_launcher_ohos/
            ├── lib/                          # Dart 代码目录
            │   ├── src/
            │   │   └── messages.g.dart       # 平台通道消息定义
            │   └── url_launcher_ohos.dart    # 插件主入口
            ├── ohos/                         # OpenHarmony 原生代码目录
            │   └── src/main/ets/components/plugin/
            │       ├── InAppBrowser.ets      # 应用内浏览器实现
            │       ├── Messages.ets          # 消息处理
            │       ├── UrlLauncher.ets       # URL 启动器实现
            │       └── UrlLauncherPlugin.ets # 插件入口
            ├── example/                      # 示例应用
            │   ├── lib/main.dart             # 示例代码
            │   └── ohos/                     # 示例应用原生代码
            ├── test/                         # 单元测试
            ├── test_driver/                  # 集成测试驱动程序
            ├── integration_test/             # 集成测试
            ├── pubspec.yaml                  # 包配置文件
            ├── README.md      # 中文文档
            └── README.en.md   # 英文文档
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues) ，当然，也非常欢迎发 [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) 共建。


## 开源协议

本项目基于 [BSD-3-Clause](LICENSE) ，请自由地享受和参与开源。

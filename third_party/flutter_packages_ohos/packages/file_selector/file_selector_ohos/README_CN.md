<div align="center">
  <h1>file_selector_ohos</h1>
</div>

本项目基于 [file_selector@1.1.0](https://pub.dev/packages/file_selector/versions/1.1.0) 开发。

## 简介

`file_selector_ohos` 是 `file_selector` 的 OpenHarmony 平台实现，为 Flutter 应用提供文件选择能力，支持选择单个文件、批量选择文件。

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

```yaml
dependencies:
  file_selector:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/file_selector/file_selector
      # ref: file_selector-v1.1.0-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令：

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `-` | `file_selector-v1.1.0-ohos-1.0.1` | `br_file_selector-v1.1.0_ohos` |
| 3.35 | `-` | `file_selector-v1.1.0-ohos-1.0.1` | `br_file_selector-v1.1.0_ohos` |
| 3.27 | `file_selector-v1.0.3-ohos-1.0.0` | `file_selector-v1.0.3-ohos-1.0.1` | `br_file_selector-v1.0.3_ohos` |
| 3.22 | `file_selector-v1.0.3-ohos-1.0.0` | `file_selector-v1.0.3-ohos-1.0.1` | `br_file_selector-v1.0.3_ohos` |
| 3.7 | `file_selector-v1.0.1-ohos-1.0.0` | `file_selector-v1.0.1-ohos-1.0.1` | `master` |

<!-- tabs:end -->

## 约束与限制

### 兼容性

在以下版本中已测试通过

1. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.2.268; ROM: 6.0.0.130 SP18;
2. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.2.268; ROM: 6.0.0.130 SP18;

### 权限要求

以下中包含 `system_basic` 权限，而默认应用权限等级为 `normal`，仅能使用 `normal` 等级的权限。安装HAP包时因权限等级不匹配导致安装失败，请参考平台官方权限管理文档进行配置。

####  在 entry 目录下的module.json5中添加权限

打开 `entry/src/main/module.json5`，添加：

```yaml
...
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

####  在 entry 目录下添加申请以上权限的原因

打开 `entry/src/main/resources/base/element/string.json`，添加：

```
...
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络"
    },
  ]
}
```

## 使用示例

```dart
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

Future<void> pickTextFile() async {
  // 导入并定义文件过滤条件
  const XTypeGroup typeGroup = XTypeGroup(
    label: 'text',
    extensions: <String>['txt', 'json'],
    uniformTypeIdentifiers: <String>['public.text'],
  );

  // 调用平台接口打开文件选择器
  final XFile? file = await FileSelectorPlatform.instance.openFile(
    acceptedTypeGroups: <XTypeGroup>[typeGroup],
  );
  if (file == null) {
    return;
  }
}
```

## 接口说明

### API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name                                                         | return value        | Description                                                  | Type     | ohos Support |
| ------------------------------------------------------------ | ------------------- | ------------------------------------------------------------ | -------- | ------------ |
| openFile({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,}) | Future<XFile?>      | 打开一个用于加载文件的文件对话框，并返回用户选择的文件。 | function | partially          |
| openFiles({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,}) | Future<List<XFile>> | 打开一个文件对话框以加载多个文件，并返回用户选择的文件列表。 | function | partially          |
| getDirectoryPath({String? initialDirectory, String? confirmButtonText, bool? canCreateDirectories,}) | Future<String?>     | 打开一个文件对话框以选择目录，并返回所选的目录路径。         | function | no           |

### Parameters

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| acceptedTypeGroups  | 可以在对话框中选择的文件类型组列表，其显示方式取决于平台。                                                                                                                                 | List<[XTypeGroup](#XTypeGroup)>?               | yes               |
| initialDirectory  | 对话框打开时将显示的目录的完整路径。如果没有提供，平台将选择一个初始位置。                                                                                                                                | String?               | yes               |
| confirmButtonText | 对话框确认按钮上的文本。如果没有提供，将使用默认的操作系统标签（例如，“Open”）。                                                                                                                                 | String?               | no              |

### XTypeGroup

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| label  | 这个类型组的“名称”或引用。                                                                                                                                 | String?               | yes               |
| extensions  | 这个组的文件扩展名                                                                                                                                 | List<String>?               | yes               |
| mimeTypes  | 这个组的 MIME 类型。                                                                                                                                 | List<String>?               | yes               |
| uniformTypeIdentifiers  | 这个组的统一类型标识符。                                                                                                                                 | List<String>?               | no              |
| webWildCards  | 这个组的网络通配符（例如：image/*，video/*）。                                                                                                                                 | List<String>?               | no              |

## 遗留问题

系统选择拉起对话框后的确认按钮不支持自定义；手机侧 file picker 拉起对话框不支持选择目录，`getDirectoryPath` 不支持；`webWildCards` 仅在 Web 平台生效；`uniformTypeIdentifiers` 是统一类型标识符（UTI）列表，仅在 iOS / macOS 平台生效。

## 目录结构

```text
file_selector_ohos/
├─ lib/                         # OpenHarmony 平台实现导出与核心逻辑
├─ ohos/                        # OpenHarmony 原生侧实现
├─ pigeons/                     # Pigeon 接口定义
├─ example/                     # 示例应用
├─ test/                        # 测试代码
├─ pubspec.yaml                 # 包配置
├─ README.md                    # 英文说明文档
└─ README_CN.md                 # 中文说明文档
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues)，当然，也非常欢迎发 [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) 共建。

## 开源协议

本项目基于 [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/file_selector/file_selector_ohos/LICENSE) ，请自由地享受和参与开源。

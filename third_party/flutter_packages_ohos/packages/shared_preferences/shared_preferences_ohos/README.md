<p align="center">
  <h1 align="center"> <code>shared_preferences</code> </h1>
</p>

本项目基于 [shared_preferences@2.5.4](https://pub.dev/packages/shared_preferences/versions/2.5.4) 的 OpenHarmony 平台实现开发。

## 简介

`shared_preferences_ohos` 为 `shared_preferences` 提供 OpenHarmony 平台存储实现，支持在设备本地持久化以下基础类型数据：

- `String`
- `int`
- `double`
- `bool`
- `List<String>`

> 注意：该插件用于轻量级键值持久化，不适合存储关键业务数据。

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

```yaml
...

dependencies:
  shared_preferences:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/shared_preferences/shared_preferences
      # ref: shared_preferences-v2.5.4-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
...
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `shared_preferences-v2.5.4-ohos-1.0.0` | `shared_preferences-v2.5.4-ohos-1.0.1` | `br_shared_preferences-v2.5.4_ohos` |
| 3.35 | `shared_preferences-v2.5.4-ohos-1.0.0` | `shared_preferences-v2.5.4-ohos-1.0.1` | `br_shared_preferences-v2.5.4_ohos` |
| 3.27 | `shared_preferences-v2.5.3-ohos-1.0.0` | `shared_preferences-v2.5.3-ohos-1.0.1` | `br_shared_preferences-v2.5.3_ohos` |
| 3.22 | `shared_preferences-v2.3.2-ohos-1.0.0` | `shared_preferences-v2.3.2-ohos-1.0.1` | `br_shared_preferences-v2.3.2_ohos` |
| 3.7 | `shared_preferences-v2.2.2-ohos-1.0.0` | `shared_preferences-v2.2.2-ohos-1.0.1` | `master` |

## 约束与限制

### 兼容性

在以下版本中已测试通过

1. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.1.268; ROM: 6.1.0.117 SP36;
2. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.1.268; ROM: 6.1.0.117 SP36;

### 权限要求

无。

### 平台差异与注意事项

- 数据类型：仅支持 `String/int/double/bool/List<String>`（与 upstream 行为一致）。
- Async 过滤能力：Async API 仅支持 `allowList` 过滤（`getPreferences/getKeys/clear`），不支持 prefix 过滤（属设计如此，非 OHOS 特有）。
- Async 默认存储名：当使用 Async `SharedPreferences` backend 且未指定 `fileName` 时，OHOS 默认使用 `${bundleName}_preferences` 作为存储名，以避免与 legacy `FlutterSharedPreferences`（固定存储名）发生读写互相覆盖；如需跨平台一致性，建议显式指定 `fileName`。
- StringList 存储协议：JSON 编码的 `List<String>` 会以 `jsonListPrefix + jsonEncode(list)` 的字符串形式落库；读取时会被还原为 `List<String>`。同时兼容历史 platformEncoded 的 list 格式用于迁移/回归。
- 数据安全：本插件不提供加密能力，数据以明文方式持久化，请勿存储敏感信息。

## 使用示例

### Async API 与后端选项（OpenHarmony 已支持）

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_ohos/shared_preferences_ohos.dart';

Future<void> asyncUsage() async {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  const SharedPreferencesAsyncOhosOptions options =
      SharedPreferencesAsyncOhosOptions(
    backend: SharedPreferencesOhosBackendLibrary.SharedPreferences,
    originalSharedPreferencesOptions: OhosSharedPreferencesStoreOptions(
      fileName: 'the_name_of_a_file',
    ),
  );

  await prefs.setString('action', 'Start', options: options);
  final String? action = await prefs.getString('action', options: options);
  print('action=$action');
}
```

## 使用说明

- `SharedPreferencesAsyncOhos`：`SharedPreferencesAsyncPlatform` 的 OpenHarmony 实现。
- 过滤能力：Async 接口当前支持 `allowList` 过滤（`getPreferences`、`clear`、`getKeys` 等）。
- 后端选项：`SharedPreferencesAsyncOhosOptions.backend` 定义了 `DataStore` 与 `SharedPreferences` 两个选项。

## 接口说明

### API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性，no 则表示不支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

#### SharedPreferences

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `getInstance()` | function | `-` | `Future<SharedPreferences>` | yes | 返回 SharedPreferences 实例 |
| `getString()` | function | `String key` | `String?` | yes | 获取当前 `SharedPreferences` 作用域内已存储的字符串 |
| `getInt()` | function | `String key` | `int?` | yes | 获取当前 `SharedPreferences` 作用域内已存储的整型值 |
| `getDouble()` | function | `String key` | `double?` | yes | 获取当前 `SharedPreferences` 作用域内已存储的浮点值 |
| `getBool()` | function | `String key` | `bool?` | yes | 获取当前 `SharedPreferences` 作用域内已存储的布尔值 |
| `getStringList()` | function | `String key` | `List<String>?` | yes | 获取当前 `SharedPreferences` 作用域内已存储的字符串列表 |
| `setString()` | function | `String key, String value` | `Future<bool>` | yes | 存储字符串 |
| `setInt()` | function | `String key, int value` | `Future<bool>` | yes | 存储整型值 |
| `setDouble()` | function | `String key, double value` | `Future<bool>` | yes | 存储浮点值 |
| `setBool()` | function | `String key, bool value` | `Future<bool>` | yes | 存储布尔值 |
| `setStringList()` | function | `String key, List<String> value` | `Future<bool>` | yes | 存储字符串列表 |
| `remove()` | function | `String key` | `Future<bool>` | yes | 删除指定键值 |
| `clear()` | function | `-` | `Future<bool>` | yes | 清除当前 `SharedPreferences` 作用域内的全部键值 |
| `reload()` | function | `-` | `Future<void>` | yes | 从磁盘重新加载当前 `SharedPreferences` 作用域内的数据 |
| `containsKey()` | function | `String key` | `bool` | yes | 检查当前 `SharedPreferences` 作用域内是否存在该键 |
| `getKeys()` | function | `-` | `Set<String>` | yes | 返回当前 `SharedPreferences` 作用域内的全部键集合 |

#### SharedPreferencesOhos

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `remove()` | method | `String key` | `Future<bool>` | yes | 删除指定键值 |
| `setValue()` | method | `String valueType, String key, Object value` | `Future<bool>` | yes | 按类型写入 `String`、`int`、`double`、`bool`、`List<String>` |
| `clear()` | method | `-` | `Future<bool>` | yes | 清除默认 legacy 前缀 `flutter.` 作用域内的数据 |
| `clearWithPrefix()` | method | `String prefix` | `Future<bool>` | yes | 按指定前缀清除数据 |
| `clearWithParameters()` | method | `ClearParameters parameters` | `Future<bool>` | yes | 按 legacy 过滤参数清除数据 |
| `getAll()` | method | `-` | `Future<Map<String, Object>>` | yes | 获取默认 legacy 前缀 `flutter.` 作用域内的全部数据 |
| `getAllWithPrefix()` | method | `String prefix` | `Future<Map<String, Object>>` | yes | 获取指定前缀作用域内的全部数据 |
| `getAllWithParameters()` | method | `GetAllParameters parameters` | `Future<Map<String, Object>>` | yes | 按 legacy 过滤参数获取全部数据 |

#### SharedPreferencesAsyncOhos

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `getKeys()` | method | `GetPreferencesParameters parameters, SharedPreferencesOptions options` | `Future<Set<String>>` | yes | 获取 Async 接口作用域内的键集合，当前支持 `allowList` 过滤 |
| `setString()` | method | `String key, String value, SharedPreferencesOptions options` | `Future<void>` | yes | 写入字符串 |
| `setInt()` | method | `String key, int value, SharedPreferencesOptions options` | `Future<void>` | yes | 写入整型值 |
| `setDouble()` | method | `String key, double value, SharedPreferencesOptions options` | `Future<void>` | yes | 写入浮点值 |
| `setBool()` | method | `String key, bool value, SharedPreferencesOptions options` | `Future<void>` | yes | 写入布尔值 |
| `setStringList()` | method | `String key, List<String> value, SharedPreferencesOptions options` | `Future<void>` | yes | 将字符串列表编码后写入 |
| `getString()` | method | `String key, SharedPreferencesOptions options` | `Future<String?>` | yes | 获取字符串 |
| `getInt()` | method | `String key, SharedPreferencesOptions options` | `Future<int?>` | yes | 获取整型值 |
| `getDouble()` | method | `String key, SharedPreferencesOptions options` | `Future<double?>` | yes | 获取浮点值 |
| `getBool()` | method | `String key, SharedPreferencesOptions options` | `Future<bool?>` | yes | 获取布尔值 |
| `getStringList()` | method | `String key, SharedPreferencesOptions options` | `Future<List<String>?>` | yes | 获取字符串列表，兼容 JSON 编码与平台编码结果 |
| `clear()` | method | `ClearPreferencesParameters parameters, SharedPreferencesOptions options` | `Future<void>` | yes | 按 Async 过滤参数清理数据，当前支持 `allowList` |
| `getPreferences()` | method | `GetPreferencesParameters parameters, SharedPreferencesOptions options` | `Future<Map<String, Object>>` | yes | 按 Async 过滤参数获取全部数据，当前支持 `allowList` |

#### SharedPreferencesAsyncOhosOptions

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `backend` | property | `SharedPreferencesOhosBackendLibrary` | `SharedPreferencesOhosBackendLibrary` | yes | Async 接口后端选项，定义 `DataStore` 与 `SharedPreferences` 两个枚举值 |
| `originalSharedPreferencesOptions` | property | `OhosSharedPreferencesStoreOptions?` | `OhosSharedPreferencesStoreOptions?` | yes | 当选择 `SharedPreferences` 后端时使用的附加配置 |

#### OhosSharedPreferencesStoreOptions

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `fileName` | property | `String?` | `String?` | yes | 指定 `SharedPreferences` 后端使用的存储文件名 |

#### 存储类型

| Name         | Description    | Type   | **ohos Support** |
| ------------ | -------------- | ------ | ---------------- |
| String       | 存储字符串值   | String | yes              |
| int          | 存储整数值     | int    | yes              |
| double       | 存储浮点数值   | double | yes              |
| bool         | 存储布尔值     | bool   | yes              |
| List<String> | 存储字符串列表 | List   | yes              |



#### 参数

| Name   | Description                                             | Type    | **ohos Support** |
| ------ | ------------------------------------------------------- | ------- | ---------------- |
| key    | 存储值的唯一标识符                                      | String  | yes              |
| value  | 要存储的值（String、int、double、bool 或 List<String>） | dynamic | yes              |
| prefix | legacy `SharedPreferences` 接口默认使用 `flutter.` 作为键前缀，用于限定 `clear()`、`getKeys()`、`containsKey()`、`reload()` 等作用范围 | String | yes |

## 目录结构

```text
shared_preferences_ohos/
├─ lib/
│  ├─ shared_preferences_ohos.dart
│  └─ src/
│     ├─ shared_preferences_ohos.dart
│     └─ shared_preferences_async_ohos.dart
├─ ohos/
├─ example/
├─ test/
└─ pubspec.yaml
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues) ，也欢迎提交 [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) 共建。

## 开源协议

本项目基于 [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/br_shared_preferences-v2.5.4_ohos/packages/shared_preferences/shared_preferences/LICENSE)，请自由地享受和参与开源。

> 模板版本: v0.0.1

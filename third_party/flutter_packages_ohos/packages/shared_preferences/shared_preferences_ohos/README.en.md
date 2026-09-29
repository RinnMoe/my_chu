<p align="center">
  <h1 align="center"> <code>shared_preferences</code> </h1>
</p>

This project is developed as the OpenHarmony platform implementation based on [shared_preferences@2.5.4](https://pub.dev/packages/shared_preferences/versions/2.5.4).

## Introduction

`shared_preferences_ohos` provides OpenHarmony storage support for `shared_preferences`, and persists the following primitive value types locally:

- `String`
- `int`
- `double`
- `bool`
- `List<String>`

> Note: This plugin is designed for lightweight key-value persistence, not for critical business data.

## Installation

Go to your project directory and add the following dependency in `pubspec.yaml`:

```yaml
...

dependencies:
  shared_preferences:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/shared_preferences/shared_preferences
      # ref: shared_preferences-v2.5.4-ohos-1.0.1
      ref: TAG  #   Select a TAG according to the TAG version table below
...
```

Execute Command

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `shared_preferences-v2.5.4-ohos-1.0.0` | `shared_preferences-v2.5.4-ohos-1.0.1` | `br_shared_preferences-v2.5.4_ohos` |
| 3.35 | `shared_preferences-v2.5.4-ohos-1.0.0` | `shared_preferences-v2.5.4-ohos-1.0.1` | `br_shared_preferences-v2.5.4_ohos` |
| 3.27 | `shared_preferences-v2.5.3-ohos-1.0.0` | `shared_preferences-v2.5.3-ohos-1.0.1` | `br_shared_preferences-v2.5.3_ohos` |
| 3.22 | `shared_preferences-v2.3.2-ohos-1.0.0` | `shared_preferences-v2.3.2-ohos-1.0.1` | `br_shared_preferences-v2.3.2_ohos` |
| 3.7 | `shared_preferences-v2.2.2-ohos-1.0.0` | `shared_preferences-v2.2.2-ohos-1.0.1` | `master` |

## Constraints

### Compatibility

Tested with the following versions:

1. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.1.268; ROM: 6.1.0.117 SP36;
2. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.1.268; ROM: 6.1.0.117 SP36;

### Permission Requirements

None.

### Platform Differences and Notes

- Data types: only `String/int/double/bool/List<String>` are supported(same as upstream behavior).
- Async filtering: Async APIs only support `allowList` filtering (`getPreferences/getKeys/clear`); prefix filtering is not supported by design (not OHOS-specific).
- Async default storage name: when using the Async `SharedPreferences` backend without specifying `fileName`, OHOS uses `${bundleName}_preferences` by default to avoid collisions with the legacy `FlutterSharedPreferences` store. For consistent cross-platform behavior, specify `fileName` explicitly.
- StringList storage protocol: JSON-encoded `List<String>` is persisted as a string in the form `jsonListPrefix + jsonEncode(list)` and is decoded back to `List<String>` on reads. Legacy platform-encoded list values are also supported for migration/regression.
- Data security: this plugin does not provide encryption; do not store sensitive data.

## Usage example

### Async API and backend options (OpenHarmony supported)

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

## Usage Notes

- `SharedPreferencesAsyncOhos`: OpenHarmony implementation of `SharedPreferencesAsyncPlatform`.
- Filtering capability: Async APIs currently support `allowList` filtering for `getPreferences`, `clear`, and `getKeys`.
- Backend options: `SharedPreferencesAsyncOhosOptions.backend` defines `DataStore` and `SharedPreferences` options.

## API Description

### API

> [!TIP] In the "ohos Support" column, `yes` means this item is supported on the ohos platform, and `no` means it is not supported. The usage is cross-platform consistent, and the behavior aligns with iOS or Android.

#### SharedPreferences

| Name | Type | Parameter Type | Return Value | OHOS Platform Support | Description |
| --- | --- | --- | --- | --- | --- |
| `getInstance()` | function | `-` | `Future<SharedPreferences>` | yes | Return a SharedPreferences instance |
| `getString()` | function | `String key` | `String?` | yes | Get the stored string value in the current legacy `SharedPreferences` scope |
| `getInt()` | function | `String key` | `int?` | yes | Get the stored integer value in the current legacy `SharedPreferences` scope |
| `getDouble()` | function | `String key` | `double?` | yes | Get the stored floating-point value in the current legacy `SharedPreferences` scope |
| `getBool()` | function | `String key` | `bool?` | yes | Get the stored boolean value in the current legacy `SharedPreferences` scope |
| `getStringList()` | function | `String key` | `List<String>?` | yes | Get the stored string list in the current legacy `SharedPreferences` scope |
| `setString()` | function | `String key, String value` | `Future<bool>` | yes | Store a string value |
| `setInt()` | function | `String key, int value` | `Future<bool>` | yes | Store an integer value |
| `setDouble()` | function | `String key, double value` | `Future<bool>` | yes | Store a floating-point value |
| `setBool()` | function | `String key, bool value` | `Future<bool>` | yes | Store a boolean value |
| `setStringList()` | function | `String key, List<String> value` | `Future<bool>` | yes | Store a string list |
| `remove()` | function | `String key` | `Future<bool>` | yes | Remove the stored value |
| `clear()` | function | `-` | `Future<bool>` | yes | Remove all stored values in the current legacy `SharedPreferences` scope |
| `reload()` | function | `-` | `Future<void>` | yes | Reload values from disk for the current legacy `SharedPreferences` scope |
| `containsKey()` | function | `String key` | `bool` | yes | Check whether a key exists in the current legacy `SharedPreferences` scope |
| `getKeys()` | function | `-` | `Set<String>` | yes | Return all keys in the current legacy `SharedPreferences` scope |

#### SharedPreferencesOhos

| Name | Type | Parameter Type | Return Value | OHOS Platform Support | Description |
| --- | --- | --- | --- | --- | --- |
| `remove()` | method | `String key` | `Future<bool>` | yes | Remove the specified key |
| `setValue()` | method | `String valueType, String key, Object value` | `Future<bool>` | yes | Write `String`, `int`, `double`, `bool`, or `List<String>` values by type |
| `clear()` | method | `-` | `Future<bool>` | yes | Clear data in the default legacy `flutter.` prefix scope |
| `clearWithPrefix()` | method | `String prefix` | `Future<bool>` | yes | Clear data with a specified prefix |
| `clearWithParameters()` | method | `ClearParameters parameters` | `Future<bool>` | yes | Clear data with legacy filter parameters |
| `getAll()` | method | `-` | `Future<Map<String, Object>>` | yes | Get all data in the default legacy `flutter.` prefix scope |
| `getAllWithPrefix()` | method | `String prefix` | `Future<Map<String, Object>>` | yes | Get all data in the specified prefix scope |
| `getAllWithParameters()` | method | `GetAllParameters parameters` | `Future<Map<String, Object>>` | yes | Get all data with legacy filter parameters |

#### SharedPreferencesAsyncOhos

| Name | Type | Parameter Type | Return Value | OHOS Platform Support | Description |
| --- | --- | --- | --- | --- | --- |
| `getKeys()` | method | `GetPreferencesParameters parameters, SharedPreferencesOptions options` | `Future<Set<String>>` | yes | Get the key set in the async scope; currently supports `allowList` filtering |
| `setString()` | method | `String key, String value, SharedPreferencesOptions options` | `Future<void>` | yes | Store a string value |
| `setInt()` | method | `String key, int value, SharedPreferencesOptions options` | `Future<void>` | yes | Store an integer value |
| `setDouble()` | method | `String key, double value, SharedPreferencesOptions options` | `Future<void>` | yes | Store a floating-point value |
| `setBool()` | method | `String key, bool value, SharedPreferencesOptions options` | `Future<void>` | yes | Store a boolean value |
| `setStringList()` | method | `String key, List<String> value, SharedPreferencesOptions options` | `Future<void>` | yes | Encode and store a string list |
| `getString()` | method | `String key, SharedPreferencesOptions options` | `Future<String?>` | yes | Get a string value |
| `getInt()` | method | `String key, SharedPreferencesOptions options` | `Future<int?>` | yes | Get an integer value |
| `getDouble()` | method | `String key, SharedPreferencesOptions options` | `Future<double?>` | yes | Get a floating-point value |
| `getBool()` | method | `String key, SharedPreferencesOptions options` | `Future<bool?>` | yes | Get a boolean value |
| `getStringList()` | method | `String key, SharedPreferencesOptions options` | `Future<List<String>?>` | yes | Get a string list with compatibility for JSON-encoded and platform-encoded results |
| `clear()` | method | `ClearPreferencesParameters parameters, SharedPreferencesOptions options` | `Future<void>` | yes | Clear data with async filter parameters; currently supports `allowList` |
| `getPreferences()` | method | `GetPreferencesParameters parameters, SharedPreferencesOptions options` | `Future<Map<String, Object>>` | yes | Get all data with async filter parameters; currently supports `allowList` |

#### SharedPreferencesAsyncOhosOptions

| Name | Type | Parameter Type | Return Value | OHOS Platform Support | Description |
| --- | --- | --- | --- | --- | --- |
| `backend` | property | `SharedPreferencesOhosBackendLibrary` | `SharedPreferencesOhosBackendLibrary` | yes | Async backend option that defines `DataStore` and `SharedPreferences` enum values |
| `originalSharedPreferencesOptions` | property | `OhosSharedPreferencesStoreOptions?` | `OhosSharedPreferencesStoreOptions?` | yes | Additional options used when the `SharedPreferences` backend is selected |

#### OhosSharedPreferencesStoreOptions

| Name | Type | Parameter Type | Return Value | OHOS Platform Support | Description |
| --- | --- | --- | --- | --- | --- |
| `fileName` | property | `String?` | `String?` | yes | Specifies the storage file name used by the `SharedPreferences` backend |

#### Storage type

| Name         | Description                 | Type   | **ohos Support** |
| ------------ | --------------------------- | ------ | ---------------- |
| String       | Store string values         | String | yes              |
| int          | Store integer values        | int    | yes              |
| double       | Store floating-point values | double | yes              |
| bool         | Store boolean values        | bool   | yes              |
| List<String> | Store string lists          | List   | yes              |

#### Parameters

| Name   | Description                                                  | Type    | **ohos Support** |
| ------ | ------------------------------------------------------------ | ------- | ---------------- |
| key    | The unique identifier for storing values                     | String  | yes              |
| value  | The value to be stored (String, int, double, bool, or List<String>) | dynamic | yes              |
| prefix | The legacy `SharedPreferences` APIs use `flutter.` as the default key prefix to scope operations such as `clear()`, `getKeys()`, `containsKey()`, and `reload()` | String | yes |

## Directory structure

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

## Contributing

If you encounter any issues during use, you can submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues). You are also very welcome to contribute through [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls).

## License

This project is licensed under [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/br_shared_preferences-v2.5.4_ohos/packages/shared_preferences/shared_preferences/LICENSE)

> Template version: v0.0.1

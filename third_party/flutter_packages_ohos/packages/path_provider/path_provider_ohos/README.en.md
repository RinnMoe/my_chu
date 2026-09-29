<p align="center">
  <h1 align="center"> <code>path_provider</code> </h1>
</p>

This project is developed based on [path_provider@2.1.5](https://pub.dev/packages/path_provider/versions/2.1.5).

## Introduction

`path_provider` is used in Flutter to obtain commonly used file system paths on devices, such as the temporary directory, application documents directory, cache directory, and external storage related paths. This implementation integrates with `path_provider` through a federated plugin, providing platform channel capabilities consistent with the official plugin on OpenHarmony.

## Installation

Enter the project directory and add the following dependency in pubspec.yaml:

```yaml
dependencies:
  path_provider:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/path_provider/path_provider
      # ref: provider-v2.1.5-ohos-1.0.1
      ref: TAG  #   Please select the TAG according to the TAG version table below
```

Run the command

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `provider-v2.1.5-ohos-1.0.0` | `provider-v2.1.5-ohos-1.0.1` | `br_path_provider-v2.1.5_ohos` |
| 3.35 | `provider-v2.1.5-ohos-1.0.0` | `provider-v2.1.5-ohos-1.0.1` | `br_path_provider-v2.1.5_ohos` |
| 3.27 | `provider-v2.1.5-ohos-1.0.0` | `provider-v2.1.5-ohos-1.0.1` | `br_path_provider-v2.1.5_ohos` |
| 3.22 | `provider-v2.1.4_ohos-1.0.0` | `provider-v2.1.4_ohos-1.0.1` | `br_path_provider-v2.1.4_ohos` |
| 3.7 | `provider-v2.1.1-ohos-1.0.0` | `provider-v2.1.1-ohos-1.0.1` | `master` |

## Constraints and Limitations

### Compatibility

Tested and passed on the following versions
1. Flutter: 3.27.5-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 5.1.0.130 SP8;
2. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;
3. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### Permission Requirements

Some permissions are system-level (`system-level`), while the default application level is `normal`, which only allows `normal` level permissions. Therefore, if you apply for system-level permissions in your application, errors may occur when installing the HAP package.

Open `entry/src/main/module.json5` and add:

```yaml
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

Open `entry/src/main/resources/base/element/string.json` and add:

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

## Usage Example

The example [`example/lib/main.dart`](./example/lib/main.dart) in this repository is consistent with the following implementation approach: both depend on `path_provider_platform_interface`, use `PathProviderPlatform.instance` to call `getTemporaryPath()`, `getApplicationDocumentsPath()`, etc.; the UI side triggers requests in button `onPressed` and displays paths or errors via `FutureBuilder`. The code snippets in this document are simplified examples; for the complete runnable version, please refer to `example/lib/main.dart`.


```dart
import 'package:flutter/material.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Future<void> logPathsFromExample() async {
  final PathProviderPlatform provider = PathProviderPlatform.instance;

  final temp = await provider.getTemporaryPath();
  debugPrint('Temporary: $temp');

  final docs = await provider.getApplicationDocumentsPath();
  debugPrint('Documents: $docs');

  final support = await provider.getApplicationSupportPath();
  debugPrint('Support: $support');

  final cache = await provider.getApplicationCachePath();
  debugPrint('Cache: $cache');
}
```

## Usage Instructions

1. Depend on `path_provider` in `pubspec.yaml` (configure the Git source and `ref` as described above); the example project will resolve to `path_provider_platform_interface` through transitive dependencies.
2. For path queries, refer to the example implementation approach: call `getTemporaryPath()` and other methods through `PathProviderPlatform.instance`, trigger via buttons on the UI side, and display results via `FutureBuilder`. The code snippets in this document are simplified examples; for the complete runnable version, please refer to `example/lib/main.dart`.

## Interface Description

### API

The following lists the support status of path capabilities related to the `path_provider` platform interface in this OHOS implementation. The application layer should still use the functions exported by the main `path_provider` package as the standard.

| Name                | Return Value                        |  Description               | Type       | OHOS Support |
|---------------------|-------------------------------------------------------------------------------------------------------|------|-------|-------------------|
| getTemporaryPath()   |   Future<String?>             |         Obtains the path of the temporary directory (not backed up) on the device, suitable for storing caches of downloaded files     | function | yes               |
| getApplicationSupportPath()   |    Future<String?>     |    Obtains the path of the application support files directory, where the application may place application support files; if the directory does not exist, it will be created automatically.         | function | yes               |
| getLibraryPath()   |    Future<String?>     |    Obtains the application's Library directory path (used on iOS/macOS platforms). OHOS does not support this; calling it will throw an `UnsupportedError`. The example application still provides a corresponding button to verify this behavior.         | function | no               |
| getApplicationDocumentsPath() |     Future<String?>  |          Obtains the path of the application files directory, where the application can place user-generated data or data that cannot be recreated by the application.       | function | yes               |
| getApplicationCachePath()   | Future<String?>       |          Obtains the path of the application cache directory, where the application may place application-specific cache files; if the directory does not exist, it will be created automatically.      | function       | yes              |
| getExternalCachePaths()     | Future<List<String?>> | Obtains the directory paths where the application's cache data can be stored externally, typically on external storage such as a separate partition or SD card. A phone may have multiple available storage directories.  | function       | yes               |
| getExternalStoragePath()    |   Future<String?>         |       Obtains the path of the application's top-level storage directory, where the application can access the top-level storage.     |        function       | yes               |
| getExternalStoragePaths([StorageDirectory](#StorageDirectory) arg_directory)   | Future<List<String?>> |   Obtains the path of the application's top-level storage directory, where application-specific data can be stored in external directories, typically on external storage such as a separate partition or SD card. A phone may have multiple available storage directories. | function       | yes               |
| getDownloadsPath()   | Future<String?>       | Obtains the path of the downloads directory; on OHOS, this is implemented based on `getExternalStoragePaths(StorageDirectory.downloads)`, and returns null when no path is available. | function | yes               |

### Properties

#### StorageDirectory

| Name              | Description                                                | Type                                        | OHOS Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  StorageDirectory.music  | Music file type for the storage directory |  enum | yes   |
|  StorageDirectory.podcasts  | Audio file type for the storage directory |  enum | yes   |
|  StorageDirectory.ringtones  | Ringtone file type for the storage directory |  enum | yes   |
|  StorageDirectory.alarms  | Alarm ringtone file type for the storage directory |  enum | yes   |
|  StorageDirectory.notifications  | Notification file type for the storage directory |  enum | yes   |
|  StorageDirectory.pictures  | Image file type for the storage directory |  enum | yes   |
|  StorageDirectory.movies  | Movie file type for the storage directory |  enum | yes   |
|  StorageDirectory.downloads  | Download file type for the storage directory |  enum | yes   |
|  StorageDirectory.dcim  | Photo and video file type for the storage directory |  enum | yes   |
|  StorageDirectory.documents  | Standard file type for the storage directory |  enum | yes   |

## Unsupported Capabilities

- `StorageDirectory.root`: The `StorageDirectory` enum of the public API **does not include** `root`, and **does not support** the `StorageDirectory.root` syntax. To obtain the root directory, please use `getExternalStoragePaths(type: null)`.
- `getLibraryPath()`: OHOS does not provide an equivalent Library directory concept as iOS/macOS. This implementation will throw `UnsupportedError('getLibraryPath is not supported on OHOS')` (consistent with the Android implementation). The example application [`example/lib/main.dart`](./example/lib/main.dart) retains the **Get Library Directory** button; clicking it will display the error message via `FutureBuilder`.

## Differences from Android

Some "external storage" related interfaces are inconsistent with Android behavior and cannot be aligned due to platform capability limitations:

- `getExternalStorageDirectory()`: Android returns the application-specific directory on external storage; OHOS returns the `files` directory within the application sandbox (internal storage).
- `getExternalCacheDirectories()`: Android may return multiple external cache directories; OHOS only returns a single application `cache` directory.
- `getExternalStorageDirectories(type)`: Android returns multiple system-level external media/storage directories; OHOS creates subdirectories by type under the `files` directory and returns a single path.

## Known Issues

## Directory Structure

```
|---- path_provider_ohos
|     |---- example                    # Example application
|           |---- lib                  # Example Dart code
|           |---- ohos                 # Example application native code
|     |---- lib                        # Dart core implementation
|           |---- path_provider_ohos.dart   # Plugin main entry
|           |---- messages.g.dart           # Platform channel message definitions
|     |---- ohos                       # OpenHarmony native code directory
|           |---- src/main/ets/components/plugin/PathProviderOhosPlugin.ets  # Plugin entry
|     |---- test                       # Unit tests
|     |---- CHANGELOG.md               # Version change log
|     |---- LICENSE                    # BSD-3-Clause
|     |---- pubspec.yaml               # Package configuration file
|     |---- README.md                  # Chinese documentation
|     |---- README.en.md               # English documentation
```

## Contributing

If you encounter any issues during use, feel free to submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues). You are also welcome to submit a [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls) to contribute.

## Open Source License

This project is licensed under [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/path_provider/path_provider_ohos/LICENSE). You are welcome to use and contribute to open source freely.

> Template version: v0.0.1

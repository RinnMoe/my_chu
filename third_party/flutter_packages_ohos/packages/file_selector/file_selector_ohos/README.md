<div align="center">
  <h1>file_selector_ohos</h1>
</div>

This project is developed based on [file_selector@1.1.0](https://pub.dev/packages/file_selector/versions/1.1.0).

## Introduction

`file_selector_ohos` is the OpenHarmony platform implementation of `file_selector`. It provides file selection capabilities for Flutter apps, including single-file selection and multi-file selection.

## Installation

Go to your project root directory and add the following dependency in `pubspec.yaml`:

<!-- tabs:start -->

```yaml
dependencies:
  file_selector:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/file_selector/file_selector
      # ref: file_selector-v1.1.0-ohos-1.0.1
      ref: TAG  #   Please select the TAG according to the TAG version table below
```

Run:

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `-` | `file_selector-v1.1.0-ohos-1.0.1` | `br_file_selector-v1.1.0_ohos` |
| 3.35 | `-` | `file_selector-v1.1.0-ohos-1.0.1` | `br_file_selector-v1.1.0_ohos` |
| 3.27 | `file_selector-v1.0.3-ohos-1.0.0` | `file_selector-v1.0.3-ohos-1.0.1` | `br_file_selector-v1.0.3_ohos` |
| 3.22 | `file_selector-v1.0.3-ohos-1.0.0` | `file_selector-v1.0.3-ohos-1.0.1` | `br_file_selector-v1.0.3_ohos` |
| 3.7 | `file_selector-v1.0.1-ohos-1.0.0` | `file_selector-v1.0.1-ohos-1.0.1` | `master` |

<!-- tabs:end -->

## Constraints and Limitations

### Compatibility

Tested and passed on the following versions:

1. Flutter: 3.41.10-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.2.268; ROM: 6.0.0.130 SP18;
2. Flutter: 3.35.8-ohos-0.0.3; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.2.268; ROM: 6.0.0.130 SP18;

### Permission Requirements

Some of the following permissions require the `system_basic` privilege level, while the default application privilege level is `normal`, which can only use `normal`-level permissions. Installation of the HAP package may fail due to privilege level mismatch. Please refer to the official platform permission management documentation for configuration.

#### Add permissions in `module.json5` under the `entry` directory

Open `entry/src/main/module.json5` and add:

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

#### Add the reason string for the above permission under the `entry` directory

Open `entry/src/main/resources/base/element/string.json` and add:

```
...
{
  "string": [
    {
      "name": "network_reason",
      "value": "Use network"
    },
  ]
}
```

## Usage Example

```dart
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

Future<void> pickTextFile() async {
  // Import and define file filter conditions
  const XTypeGroup typeGroup = XTypeGroup(
    label: 'text',
    extensions: <String>['txt', 'json'],
    uniformTypeIdentifiers: <String>['public.text'],
  );

  // Open file picker through platform interface
  final XFile? file = await FileSelectorPlatform.instance.openFile(
    acceptedTypeGroups: <XTypeGroup>[typeGroup],
  );
  if (file == null) {
    return;
  }
}
```

## API Reference

### API

> [!TIP] In the "ohos Support" column, yes means the property is supported on ohos, no means not supported, and partially means partially supported. Usage is cross-platform consistent, and behavior is aligned with iOS or Android.

| Name                                                         | return value        | Description                                                  | Type     | ohos Support |
| ------------------------------------------------------------ | ------------------- | ------------------------------------------------------------ | -------- | ------------ |
| openFile({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,}) | Future<XFile?>      | Opens a file dialog for loading files and returns the file selected by the user. | function | partially          |
| openFiles({List<[XTypeGroup](#XTypeGroup)>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText,}) | Future<List<XFile>> | Opens a file dialog for loading files and returns the file response list selected by the user. | function | partially          |
| getDirectoryPath({String? initialDirectory, String? confirmButtonText, bool? canCreateDirectories,}) | Future<String?>     | Opens a file dialog for selecting a directory and returns the selected directory path. | function | no           |

### Parameters

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| acceptedTypeGroups  | A list of file type groups that can be selected in the dialog. The display behavior depends on the platform.                                                                                                                                 | List<[XTypeGroup](#XTypeGroup)>?               | yes               |
| initialDirectory  | The full path of the directory displayed when the dialog opens. If not provided, the platform chooses an initial location.                                                                                                                                | String?               | yes               |
| confirmButtonText | Text on the dialog confirm button. If not provided, the default OS label is used (for example, "Open").                                                                                                                                 | String?               | no              |

### XTypeGroup

| Name               | Description                                                                                                                                                                         | Type                        | ohos Support |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------|
| label  | The "name" or reference of this type group.                                                                                                                                 | String?               | yes               |
| extensions  | File extensions for this group.                                                                                                                                 | List<String>?               | yes               |
| mimeTypes  | MIME types for this group.                                                                                                                                 | List<String>?               | yes               |
| uniformTypeIdentifiers  | Uniform type identifiers for this group.                                                                                                                                 | List<String>?               | no              |
| webWildCards  | Web wildcards for this group (for example: image/*, video/*).                                                                                                                                 | List<String>?               | no              |

## Known Issues

The confirm button text in the system picker dialog cannot be customized. Directory selection is not supported in picker dialogs on phone devices, and `getDirectoryPath` is not supported. `webWildCards` only takes effect on the Web platform. `uniformTypeIdentifiers` is a list of UTIs and only takes effect on iOS/macOS platforms.

## Directory Structure

```text
file_selector_ohos/
├─ lib/                         # OpenHarmony platform implementation export and core logic
├─ ohos/                        # OpenHarmony native implementation
├─ pigeons/                     # Pigeon interface definitions
├─ example/                     # Example app
├─ test/                        # Test code
├─ pubspec.yaml                 # Package configuration
├─ README.md                    # English documentation
└─ README_CN.md                 # Chinese documentation
```

## Contributing

If you find any issues during usage, feel free to submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues). PR contributions are also welcome: [PR](https://gitcode.com/CPF-Flutter/flutter_packages/pulls).

## License

This project is licensed under [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/file_selector/file_selector_ohos/LICENSE). Feel free to use it and contribute to open source.

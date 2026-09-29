# OpenHarmony Flutter plugin adaptations

These source-controlled packages are the stable OpenHarmony adaptations used
with Flutter OH 3.41.10. Each package retains its upstream package name and
public API; only plugin metadata and the platform-specific OHOS implementation
add Harmony support.

- `packages/shared_preferences/shared_preferences` and
  `packages/shared_preferences/shared_preferences_ohos` come from
  `br_shared_preferences-v2.5.4_ohos` at commit
  `4a7a536bba8447c7d4eacde2fb1a2e0fbe2da044` in
  [`openharmony-tpc/flutter_packages`](https://gitcode.com/openharmony-tpc/flutter_packages).
- `packages/path_provider/path_provider` and
  `packages/path_provider/path_provider_ohos` come from
  `br_path_provider-v2.1.5_ohos` at commit
  `d4e49daa0acbd0bc419d58b1da27d64d44fab54b` in
  [`openharmony-sig/flutter_packages`](https://gitcode.com/openharmony-sig/flutter_packages).
- `packages/url_launcher/url_launcher_ohos` comes from the stable
  `url_launcher_v6.3.2-ohos-1.0.2` tag at commit
  `f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b` in
  [`oh-flutter/flutter_packages`](https://gitcode.com/oh-flutter/flutter_packages).
  MyCHU keeps the hosted `url_launcher` package for Android/iOS and selects this
  federated adapter only on OHOS.
- `packages/file_selector/file_selector_ohos` comes from the stable
  `file_selector-v1.1.0-ohos-1.0.2` tag at commit
  `05111855c6772411f39d10aac43c8a276251c1d3` in
  [`oh-flutter/flutter_packages`](https://gitcode.com/oh-flutter/flutter_packages).
  MyCHU keeps the hosted `file_selector` package for other platforms and selects
  this federated adapter only on OHOS.

The source was archived from those exact commits. The package-local license and
attribution files are retained. Update each fork only after checking the
Flutter 3.41 OHOS compatibility and rerunning the MyCHU Harmony build.

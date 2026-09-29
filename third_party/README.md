# MyCHU pinned plugin forks

`onnxruntime_ohos/` contains the pinned OpenHarmony ONNX Runtime binaries used
only by the Harmony captcha OCR bridge. Its `UPSTREAM.md` records provenance,
checksums, supported ABIs, and license files.

These packages are explicit, source-controlled forks of the published Flutter
packages used by MyCHU. They keep the upstream package names and public APIs so
application code does not need a platform-specific branch.

- `flutter_secure_storage`: based on 9.2.4; the OHOS adaptation uses HUKS with
  RSA-OAEP and AES-GCM. See its `README.openharmony.md` for source commits and
  the credential-storage constraints.
- `flutter_inappwebview_ohos`: vendored from OpenHarmony-SIG's
  `6.1.5-ohos-1.0.0` commit `528fa913763148719cde7dae2dc22dc33f15da36`.
  The local CookieManager patch removes HttpOnly cookies and awaits persistence;
  Android/iOS continue using hosted `flutter_inappwebview` 6.1.5. See
  `doc/platform/harmonyos.md` for emulator evidence and API limits.
- `flutter_blue_plus_ohos`: OHOS-only BLE Central implementation vendored from
  CPF-Flutter's `1.33.5-ohos-1.0.0` tag at commit
  `2f181368b1f1a21fa2b35ff53797426e74355c25`. The Dart API and Harmony plugin
  are isolated from the existing Android/iOS `flutter_blue_plus` dependency.
  See its `UPSTREAM.md` and `doc/platform/harmonyos.md` for provenance and
  platform limits.
- `flutter_packages_ohos`: pinned stable OHOS adaptations for `shared_preferences`
  2.5.4 and `path_provider` 2.1.5; see its README for source commits.
Update a retained fork from upstream deliberately and verify the affected
platform builds before changing its override.

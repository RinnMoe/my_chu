# OpenHarmony adaptation

This package starts from `flutter_secure_storage` 9.2.4. Its Dart API and
Android/iOS implementations remain the published source. The added `ohos/`
module is adapted from OpenHarmony-SIG's `br_v9.2.4_ohos` implementation at
commit `67c7b82e85b08a649dfd4f2bb0c455011a9384fa`.

MyCHU's OHOS implementation uses OpenHarmony Universal Keystore Kit (HUKS) to
hold the RSA key, RSA-OAEP to wrap the AES key, and AES-GCM for values stored in
app-private Preferences. The defaults are fixed in both Dart options and the
native cipher factory. Storage errors are returned to Dart instead of being
reported as successful empty reads or writes. Algorithm changes fail closed;
they do not clear or rewrite existing credentials automatically.

The HUKS cipher adaptation is based on
[`Csy_Gitee/flutter_secure_storage`](https://gitee.com/Csy_Gitee/flutter_secure_storage)
at commit `f1a8ada0a000f3c3d0e2ad51eed3b86b57969652`. OpenHarmony plugin files
retain their Apache-2.0 headers; see `LICENSE-Apache-2.0`. The package's
published Dart and Android/iOS code retains its original `LICENSE`.

Update this fork only after reviewing the upstream API, key lifecycle, error
handling, and encryption behavior. Validate the HUKS operations on supported
HarmonyOS devices before enabling credential storage in a release build.

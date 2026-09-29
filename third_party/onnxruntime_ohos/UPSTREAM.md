# ONNX Runtime OHOS binaries

- Upstream: [csukuangfj/onnxruntime-libs](https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.27.0)
- Runtime: ONNX Runtime 1.27.0 for OpenHarmony.
- Architectures: `x86_64` and `arm64-v8a`.
- Upstream ONNX Runtime source commit: `8f0278c77bf44b0cc83c098c6c722b92a36ac4b5`.
- Downloaded release asset SHA-256:
  - `onnxruntime-ohos-x86_64-1.27.0.zip`: `5f695952ddad9f08a7e42fb98656f37687246ac315943c76c4452f4026cd260c`
  - `onnxruntime-ohos-arm64-v8a-1.27.0.zip`: `6891743ed53e370f643a6ae55d7a56dd9f3b22151ec195202c09ee4234466b7c`
- `lib/arm64-v8a/libonnxruntime.so` is copied unchanged from the pinned release archive.
- `lib/x86_64/libonnxruntime.so` is rebuilt from the pinned source commit with the release's [HarmonyOS CMake workflow](https://raw.githubusercontent.com/csukuangfj/onnxruntime-libs/v1.27.0/.github/workflows/harmony-os-shared.yaml), using Harmony SDK 26.0.0.105 / Clang 15.0.4. The local compiler needed a compatibility-only rewrite of two structured bindings in `onnxruntime/core/session/model_editor_c_api.cc`; the exact patch is in `patches/model_editor_clang15_compat.patch` and does not change runtime behavior. The rebuilt file SHA-256 is `A8359507AE9D6B4AAE93FBF990CFFAD648B8BEABD02FA43B37B3990F6A57D9C1`.
- The C/C++ headers are from the pinned release archive. The rebuilt `x86_64` binary was installed in the x86_64 Harmony emulator and passed the local captcha OCR Probe; the original archived x86_64 binary did not load the N-API bridge in that environment.
- License and notices are kept in `LICENSE` and `ThirdPartyNotices.txt`.

The existing Android/iOS `flutter_onnxruntime` dependency remains unchanged. This vendored runtime is used only by the Harmony captcha OCR bridge.

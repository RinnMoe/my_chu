# ONNX Runtime resolves these Java classes from JNI during inference. Flutter's
# Android Gradle plugin enables R8 for release builds by default.
-keep class ai.onnxruntime.** { *; }

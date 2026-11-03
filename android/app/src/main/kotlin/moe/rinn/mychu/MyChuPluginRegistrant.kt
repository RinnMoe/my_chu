package moe.rinn.mychu

import io.flutter.Log
import io.flutter.embedding.engine.FlutterEngine

/**
 * 手动插件注册表：与 `GeneratedPluginRegistrant` 保持一致，但**不注册 Mapbox**。
 *
 * Mapbox 原生 SDK 在插件 attach 时初始化（约 300 ms），而用户多数冷启动不会
 * 打开地图。`MainActivity` 关闭 Flutter 的自动注册并调用本类；地图页首次
 * 打开时再经 `mychu/mapbox_lazy` 通道注册 `MapboxMapsPlugin`。
 *
 * 维护要求：新增/移除 Flutter 插件时，除 `GeneratedPluginRegistrant` 外必须同步
 * 修改本文件（Mapbox 例外，它只在懒加载路径注册）。
 */
object MyChuPluginRegistrant {
    private const val TAG = "MyChuPluginRegistrant"

    @JvmStatic
    fun registerWith(flutterEngine: FlutterEngine) {
        add(flutterEngine) { dev.fluttercommunity.plus.device_info.DeviceInfoPlusPlugin() }
        add(flutterEngine) { io.material.plugins.dynamic_color.DynamicColorPlugin() }
        add(flutterEngine) { dev.flutter.packages.file_selector_android.FileSelectorAndroidPlugin() }
        add(flutterEngine) { com.lib.flutter_blue_plus.FlutterBluePlusPlugin() }
        add(flutterEngine) { com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin() }
        add(flutterEngine) { net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin() }
        add(flutterEngine) { com.masicai.flutteronnxruntime.FlutterOnnxruntimePlugin() }
        add(flutterEngine) { io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin() }
        add(flutterEngine) { com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin() }
        add(flutterEngine) { com.baseflow.geolocator.GeolocatorPlugin() }
        add(flutterEngine) { com.github.dart_lang.jni.JniPlugin() }
        add(flutterEngine) { com.github.dart_lang.jni_flutter.JniFlutterPlugin() }
        add(flutterEngine) { dev.steenbakker.mobile_scanner.MobileScannerPlugin() }
        add(flutterEngine) { dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin() }
        add(flutterEngine) { com.baseflow.permissionhandler.PermissionHandlerPlugin() }
        add(flutterEngine) { io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin() }
        add(flutterEngine) { io.flutter.plugins.urllauncher.UrlLauncherPlugin() }
    }

    private inline fun add(
        flutterEngine: FlutterEngine,
        factory: () -> io.flutter.embedding.engine.plugins.FlutterPlugin,
    ) {
        try {
            flutterEngine.plugins.add(factory())
        } catch (error: Exception) {
            Log.e(TAG, "Error registering plugin", error)
        }
    }
}

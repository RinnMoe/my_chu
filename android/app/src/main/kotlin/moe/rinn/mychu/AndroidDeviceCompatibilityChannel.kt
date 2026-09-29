package moe.rinn.mychu

import android.content.Context
import android.os.Build
import com.hjq.device.compat.DeviceBrand
import com.hjq.device.compat.DeviceMarketName
import com.hjq.device.compat.DeviceOs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host-only Android device compatibility bridge.
 *
 * DeviceCompat may use Android SystemProperties internally, with getprop or
 * /system/build.prop fallbacks. The MyCHU bridge deliberately exposes neither
 * arbitrary property names or raw values nor a shell command surface to Dart
 * code.
 */
object AndroidDeviceCompatibilityChannel {
    private const val CHANNEL = "mychu/android_device_compatibility"

    private val featureChecks: LinkedHashMap<String, () -> Boolean> = linkedMapOf(
        "hyper_os" to { DeviceOs.isHyperOs() },
        "hyper_os_by_china" to { DeviceOs.isHyperOsByChina() },
        "hyper_os_by_global" to { DeviceOs.isHyperOsByGlobal() },
        "hyper_os_optimization" to { DeviceOs.isHyperOsOptimization() },
        "miui" to { DeviceOs.isMiui() },
        "miui_by_china" to { DeviceOs.isMiuiByChina() },
        "miui_by_global" to { DeviceOs.isMiuiByGlobal() },
        "miui_optimization" to { DeviceOs.isMiuiOptimization() },
        "realme_ui" to { DeviceOs.isRealmeUi() },
        "color_os" to { DeviceOs.isColorOs() },
        "origin_os" to { DeviceOs.isOriginOs() },
        "funtouch_os" to { DeviceOs.isFuntouchOs() },
        "magic_os" to { DeviceOs.isMagicOs() },
        "harmony_os" to { DeviceOs.isHarmonyOs() },
        "harmony_os_next_android_compatible" to {
            DeviceOs.isHarmonyOsNextAndroidCompatible()
        },
        "emui" to { DeviceOs.isEmui() },
        "one_ui" to { DeviceOs.isOneUi() },
        "oxygen_os" to { DeviceOs.isOxygenOs() },
        "h2_os" to { DeviceOs.isH2Os() },
        "flyme" to { DeviceOs.isFlyme() },
        "red_magic_os" to { DeviceOs.isRedMagicOs() },
        "nebula_ai_os" to { DeviceOs.isNebulaAiOs() },
        "my_os" to { DeviceOs.isMyOs() },
        "mifavor_ui" to { DeviceOs.isMifavorUi() },
        "smartisan_os" to { DeviceOs.isSmartisanOs() },
        "eui" to { DeviceOs.isEui() },
        "zux_os" to { DeviceOs.isZuxOs() },
        "zui" to { DeviceOs.isZui() },
        "nubia_ui" to { DeviceOs.isNubiaUi() },
        "obric_ui" to { DeviceOs.isObricUi() },
        "rog_ui" to { DeviceOs.isRogUi() },
        "ui_360" to { DeviceOs.is360Ui() },
    )

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getProfile" -> result.success(profile(context))
                "supportsFeature" -> {
                    val feature = call.argument<String>("feature")
                    result.success(supportsFeature(feature))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun profile(context: Context): Map<String, Any?> {
        val osMajorVersion = runCatching { DeviceOs.getOsBigVersionCode() }
            .getOrDefault(-1)
            .takeIf { it >= 0 }
        return mapOf(
            "brandName" to safeText(runCatching { DeviceBrand.getBrandName() }.getOrNull()),
            "marketName" to safeText(
                runCatching { DeviceMarketName.getMarketName(context) }.getOrNull(),
            ),
            "osName" to safeText(runCatching { DeviceOs.getOsName() }.getOrNull()),
            "osVersionName" to safeText(
                runCatching { DeviceOs.getOsVersionName() }.getOrNull(),
            ),
            "osMajorVersion" to osMajorVersion,
            "androidSdkInt" to Build.VERSION.SDK_INT,
        )
    }

    private fun supportsFeature(feature: String?): Boolean {
        val check = feature?.takeIf(::isKnownFeature)?.let { featureChecks[it] }
            ?: return false
        return safeBoolean(check)
    }

    internal fun isKnownFeature(feature: String?): Boolean {
        return feature != null && featureChecks.containsKey(feature)
    }

    private fun safeBoolean(check: () -> Boolean): Boolean {
        return runCatching { check() }.getOrDefault(false)
    }

    private fun safeText(value: String?): String? {
        val normalized = value
            ?.trim()
            ?.replace(Regex("[\\u0000-\\u001F\\u007F]"), " ")
            ?.take(128)
            ?.takeIf { it.isNotBlank() }
        return normalized
    }
}

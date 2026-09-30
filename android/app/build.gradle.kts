import java.io.FileInputStream
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun readDartDefine(name: String): String? {
    val encodedDefines = project.findProperty("dart-defines")?.toString() ?: return null
    return encodedDefines
        .split(",")
        .asSequence()
        .mapNotNull { encodedDefine ->
            runCatching {
                String(
                    Base64.getDecoder().decode(encodedDefine),
                    StandardCharsets.UTF_8,
                )
            }.getOrNull()
        }
        .firstOrNull { it.startsWith("$name=") }
        ?.substringAfter("=")
}

val configuredBuildChannel = System.getenv("MYCHU_BUILD_CHANNEL")
    ?.trim()
    ?.lowercase()
    ?.takeIf { it.isNotEmpty() }
val buildChannel = configuredBuildChannel ?: "official"
require(buildChannel == "official" || buildChannel == "preview") {
    "MYCHU_BUILD_CHANNEL must be official or preview, got '$buildChannel'."
}
val dartBuildChannel = readDartDefine("MYCHU_BUILD_CHANNEL")
    ?.trim()
    ?.lowercase()
    ?: "official"
require(dartBuildChannel == buildChannel) {
    "MYCHU_BUILD_CHANNEL mismatch: Gradle environment is '$buildChannel', " +
        "but Flutter dart-define is '$dartBuildChannel'."
}

val splitPerAbi = project.findProperty("split-per-abi") == "true"
val releaseBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}
val signingPropertiesFile = rootProject.file(
    if (buildChannel == "preview") "preview-key.properties" else "key.properties",
)
val hasSigningKeystore = signingPropertiesFile.isFile
val signingProperties = Properties().apply {
    if (hasSigningKeystore) {
        FileInputStream(signingPropertiesFile).use { load(it) }
    }
}

fun requiredKeystoreProperty(name: String): String {
    val value = signingProperties.getProperty(name)
    require(!value.isNullOrBlank()) {
        "Missing '$name' in ${signingPropertiesFile.name}."
    }
    return value
}

val releaseStoreFile =
    if (hasSigningKeystore) {
        rootProject.file(requiredKeystoreProperty("storeFile"))
    } else {
        null
    }

android {
    namespace = "moe.rinn.mychu"
    compileSdk = 36
    compileSdkMinor = 1
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "moe.rinn.mychu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // ABI-split releases previously used 2000 + logical build number for
        // arm64 (for example 0.3.0+4 -> 2004). Preserve that monotonic
        // sequence so a new release can update those installed packages.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "MYCHU_BUILD_CHANNEL", "\"$buildChannel\"")
        resValue("string", "app_name", "MyCHU")
        if (releaseBuildRequested && !splitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }

    signingConfigs {
        create("release") {
            val store = releaseStoreFile
            if (store != null) {
                require(store.isFile) {
                    "Release keystore does not exist: ${store.absolutePath}"
                }
                keyAlias = requiredKeystoreProperty("keyAlias")
                keyPassword = requiredKeystoreProperty("keyPassword")
                storeFile = store
                storePassword = requiredKeystoreProperty("storePassword")
            }
        }
    }
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "MyCHU Debug")
        }
        getByName("profile") {
            applicationIdSuffix = ".profile"
            resValue("string", "app_name", "MyCHU Profile")
        }
        release {
            if (buildChannel == "preview") {
                applicationIdSuffix = ".preview"
                resValue("string", "app_name", "MyCHU Preview")
            }
            signingConfig = signingConfigs.getByName("release")
        }
    }

}

androidComponents {
    beforeVariants { variant ->
        if (buildChannel == "preview" && variant.buildType != "release") {
            variant.enable = false
        }
    }
    onVariants { variant ->
        if (variant.buildType == "release") {
            variant.outputs.forEach { output ->
                output.versionCode.set(2000 + flutter.versionCode)
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // flutter_local_notifications 需要 core library desugaring。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Android 设备品牌、厂商系统与市场机型名识别。
    implementation("com.github.getActivity:DeviceCompat:2.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // Native home-screen widgets.
    implementation("androidx.glance:glance-appwidget:1.2.0")
    // LeakCanary 只用于 Android Debug 生命周期泄漏检查，不进入 Profile/Release。
    debugImplementation("com.squareup.leakcanary:leakcanary-android:2.14")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}

// 独立工作树可以编译 debug 变体；任何 release 任务仍必须显式提供签名文件。
tasks.configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        doFirst {
            require(hasSigningKeystore && releaseStoreFile?.isFile == true) {
                "Missing ${signingPropertiesFile.name}; configure the $buildChannel signing key before building a release APK."
            }
        }
    }
}

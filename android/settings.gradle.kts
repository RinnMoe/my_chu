import org.gradle.api.initialization.resolve.RepositoriesMode
import org.gradle.authentication.http.BasicAuthentication

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false
}

val flutterStorageBaseUrl =
    System.getenv("FLUTTER_STORAGE_BASE_URL") ?: "https://storage.googleapis.com"
val flutterEngineRepository = run {
    val properties = java.util.Properties()
    file("local.properties").inputStream().use { properties.load(it) }
    val sdkPath = properties.getProperty("flutter.sdk")
    val realm =
        sdkPath
            ?.let { java.io.File(it, "bin/cache/engine.realm") }
            ?.takeIf { it.isFile }
            ?.readText()
            ?.trim()
            .orEmpty()
    "$flutterStorageBaseUrl/${if (realm.isEmpty()) "" else "$realm/"}download.flutter.io"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven(url = "https://maven.aliyun.com/repository/public")
        maven(url = flutterEngineRepository)
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            credentials {
                username = "mapbox"
                password =
                    providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN").orNull
                        ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN").orEmpty()
            }
            authentication {
                create<BasicAuthentication>("basic")
            }
            content {
                includeGroupByRegex("com\\.mapbox(\\..*)?")
            }
        }
        exclusiveContent {
            forRepository {
                maven {
                    url = uri("https://jitpack.io")
                }
            }
            filter {
                includeGroup("com.github.getActivity")
            }
        }
    }
}

include(":app")

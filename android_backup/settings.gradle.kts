pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = settingsDir.resolve("local.properties")

        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use {
                properties.load(it)
            }
        }

        val sdkDir = properties.getProperty("flutter.sdk")
            ?: System.getenv("FLUTTER_ROOT")

        requireNotNull(sdkDir) {
            "Flutter SDK not found. Define flutter.sdk in local.properties or FLUTTER_ROOT env variable."
        }

        sdkDir
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
}

include(":app")



import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// 讀取 APK 簽署設定
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use {
        keystoreProperties.load(it)
    }
}

// 檢查正式版簽署資料是否完整
val hasReleaseKey = listOf(
    "keyAlias",
    "keyPassword",
    "storeFile",
    "storePassword"
).all {
    !keystoreProperties.getProperty(it).isNullOrBlank()
}

android {
    
    namespace = "com.med.myproject"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.med.myproject"

        // 保留 LINE SDK 所需的最低 Android 版本設定
        minSdk = 24

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // 僅供本機測試
                signingConfigs.getByName("debug")
            }
        }

        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Kotlin JVM 版本
kotlin {
    compilerOptions {
        jvmTarget.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        )
    }
}

flutter {
    source = "../.."
}
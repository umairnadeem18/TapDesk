import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing.
//
// The keystore and its passwords live OUTSIDE the repository, in
// D:\Development\TapDesk-Secrets\, and only this properties file - which is
// gitignored - points at them. Losing that keystore means we can never publish
// an update to an app that is already installed, so it is backed up separately
// (plan task 7.2).
//
// key.properties is optional: without it a release build falls back to debug
// signing, which is useful for a throwaway local build and useless for
// anything a user installs.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    namespace = "app.tapdesk.tapdesk_mobile"
    compileSdk = flutter.compileSdkVersion

    // ndkVersion is deliberately NOT set. TapDesk compiles no native code of
    // its own - every plugin we use ships prebuilt .so files - so the NDK is
    // never needed. Leaving Flutter's generated `ndkVersion = ...` in place
    // made AGP try to auto-install NDK 28.x, which failed on this machine and
    // failed the whole build for no useful reason. Removing it saves a ~1 GB
    // download on a slow connection.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.tapdesk.tapdesk_mobile"
        // Android 8.0. Chosen deliberately rather than tracking Flutter's
        // default: the PRD targets Android 8+, and minSdk 26 is also what the
        // camera/keystore APIs we rely on are comfortable on.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with our own keystore when one is configured, so an
            // installed app can be updated later. Never with the debug key:
            // Google Play rejects debug-signed uploads, and a debug key that
            // changes per machine breaks updates.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

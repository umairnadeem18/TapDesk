plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
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
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

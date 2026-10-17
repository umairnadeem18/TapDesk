# Flutter's own rules are applied automatically by the Flutter Gradle plugin;
# this file only needs to cover things Flutter cannot see.

# MLKit (used by mobile_scanner) loads barcode models reflectively.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.**

# Flutter's embedding references Play Core's deferred-component API
# (FlutterPlayStoreSplitApplication, PlayStoreDeferredComponentManager). TapDesk
# ships as one APK with no on-demand Play modules, so those classes are absent
# by design. R8 treats them as a hard error unless told to ignore them; without
# this the release build fails at :app:minifyReleaseWithR8.
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Flutter plugin registrant is generated, but keep the entry points so R8
# cannot strip them from a release build.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# pystray/PySide6 are the desktop side; nothing Android-side needs these, but
# guard against a transitive dependency pulling them in.
-dontwarn com.google.jni.**

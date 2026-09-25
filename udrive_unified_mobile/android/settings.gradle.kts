pluginManagement {
    val flutterSdkPath = run {
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

// Versions are pinned to Flutter's enforced floors, not above them.
//
// Flutter's DependencyVersionChecker fails the build below Gradle 8.14.0,
// AGP 8.11.1 and Kotlin 2.2.20. Deliberately staying on AGP 8.x rather than
// 9.x: AGP 9 reads only the new DSL interface, which would need this file and
// app/build.gradle.kts rewritten - a separate job from shipping this release.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

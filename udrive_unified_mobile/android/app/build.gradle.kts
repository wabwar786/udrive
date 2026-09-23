import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing (Google Play upload key)
//
// Local builds read android/key.properties (never commit it):
//     storePassword=...
//     keyPassword=...
//     keyAlias=upload
//     storeFile=upload-keystore.jks      (path relative to android/app)
//
// CI builds use the environment variables UDRIVE_KEYSTORE_PATH,
// UDRIVE_KEYSTORE_PASSWORD, UDRIVE_KEY_ALIAS and UDRIVE_KEY_PASSWORD instead.
//
// Without either, a release build is signed with the debug key so testers can
// still install an APK, but Google Play will refuse that file. Publishing is
// guarded: `flutter build appbundle` fails loudly when no upload key is set.
// ---------------------------------------------------------------------------
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signingValue(propertyKey: String, envKey: String): String? =
    (keystoreProperties.getProperty(propertyKey) ?: System.getenv(envKey))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

val uploadStoreFile = signingValue("storeFile", "UDRIVE_KEYSTORE_PATH")
val uploadStorePassword = signingValue("storePassword", "UDRIVE_KEYSTORE_PASSWORD")
val uploadKeyAlias = signingValue("keyAlias", "UDRIVE_KEY_ALIAS")
val uploadKeyPassword = signingValue("keyPassword", "UDRIVE_KEY_PASSWORD")
val hasUploadKey = listOf(uploadStoreFile, uploadStorePassword, uploadKeyAlias, uploadKeyPassword)
    .all { it != null }

android {
    namespace = "com.wabwar.udrive"
    // Google Play requires new apps and updates to target Android 16 (API 36)
    // from 31 Aug 2026. Never go below 36 even on an older Flutter SDK.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Permanent Play Store identity. Never change after the first upload.
        applicationId = "com.wabwar.udrive"
        minSdk = 23
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Falls back to an empty string so a developer without a key can still
        // build and run; the map area simply renders blank until a key is set.
        manifestPlaceholders["MAPS_API_KEY"] =
            (project.findProperty("maps_key") ?: "") as String
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadStoreFile!!)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// An app bundle exists only to be uploaded to Google Play, and Play rejects
// debug-signed bundles. Stop early with a clear message instead.
//
// Match the task by its exact name. An earlier version tested
// name.startsWith("bundle") && name.endsWith("Release"), which also matched
// bundleLibCompileToJarRelease and bundleLibRuntimeToJarRelease - tasks AGP
// creates for every library module, and every Flutter plugin is one. That made
// plain `flutter build apk` fail with a message about app bundles.
//
// allTasks spans the whole build, not just :app, so only an app module's
// bundleRelease can match this: library modules never produce that name.
gradle.taskGraph.whenReady {
    val buildingBundle = allTasks.any { it.name == "bundleRelease" }
    if (buildingBundle && !hasUploadKey) {
        throw GradleException(
            "No upload key configured. Create android/key.properties (see " +
                "PLAY_STORE_RELEASE.md) before running 'flutter build appbundle'."
        )
    }
}

flutter {
    source = "../.."
}

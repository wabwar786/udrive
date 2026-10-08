package com.wabwar.udrive

import android.content.Context
import android.os.Build
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Keeps the screen on while a live ride is open (see lib/core/services/screen_awake.dart).
    //
    // The app shares the driver's location only while it is in front: there is
    // no background-location permission. When the screen switched off after
    // thirty seconds Android paused the app, the GPS stopped, and the customer
    // watched the car stand still. This flag only stops the screen timing out;
    // it needs no permission and asks the Play Store for nothing.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "udrive/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Phone and app details for Admin → App usage (lib/core/telemetry/usage_ping.dart).
        // Nothing here needs a permission: the network operator name is public,
        // and no IMEI, phone number, account or location is read.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "udrive/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> {
                        val info = try {
                            packageManager.getPackageInfo(packageName, 0)
                        } catch (e: Exception) {
                            null
                        }
                        val code = if (info == null) null
                            else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toString()
                            else @Suppress("DEPRECATION") info.versionCode.toLong().toString()
                        val carrier = try {
                            (getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager)?.networkOperatorName
                        } catch (e: Exception) {
                            null
                        }
                        result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "model" to Build.MODEL,
                                "osVersion" to Build.VERSION.RELEASE,
                                "sdk" to Build.VERSION.SDK_INT,
                                "appVersion" to info?.versionName,
                                "buildNumber" to code,
                                "carrier" to carrier,
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

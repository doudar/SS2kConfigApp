package com.example.ss2kconfigapp

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val powerChannelName = "com.example.ss2kconfigapp/power"
	private var workoutPipChannel: MethodChannel? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		workoutPipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.smartspin2k.app/workout_pip").apply {
			setMethodCallHandler { call, result ->
				when (call.method) {
					"isSupported" -> result.success(supportsWorkoutPip())
					"enter" -> result.success(enterWorkoutPip())
					else -> result.notImplemented()
				}
			}
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, powerChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getPelotonDeviceInfo" -> {
						result.success(getPelotonDeviceInfo())
					}
					"isIgnoringBatteryOptimizations" -> {
						result.success(isIgnoringBatteryOptimizations())
					}
					"requestIgnoreBatteryOptimizations" -> {
						requestIgnoreBatteryOptimizations()
						result.success(true)
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun supportsWorkoutPip(): Boolean =
		Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
			packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

	private fun enterWorkoutPip(): Boolean {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !supportsWorkoutPip()) return false
		val params = PictureInPictureParams.Builder().setAspectRatio(Rational(2, 1)).build()
		return try {
			enterPictureInPictureMode(params)
		} catch (_: IllegalStateException) {
			// The activity may have left the foreground during the menu transition.
			false
		}
	}

	override fun onPictureInPictureModeChanged(inPictureInPictureMode: Boolean, newConfig: Configuration) {
		super.onPictureInPictureModeChanged(inPictureInPictureMode, newConfig)
		workoutPipChannel?.invokeMethod("modeChanged", inPictureInPictureMode)
	}

	override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
		workoutPipChannel?.setMethodCallHandler(null)
		workoutPipChannel = null
		super.cleanUpFlutterEngine(flutterEngine)
	}

	private fun getPelotonDeviceInfo(): Map<String, Any> {
		val identifiers = listOf(
			Build.MODEL,
			Build.PRODUCT,
			Build.DEVICE,
		).map { it.lowercase() }

		val isPelotonBrand =
			Build.BRAND.equals("Peloton", ignoreCase = true) ||
				Build.MANUFACTURER.equals("Peloton", ignoreCase = true)
		val isPelotonModel = identifiers.any { identifier ->
			identifier.startsWith("pltn-") ||
				identifier.startsWith("rb1v") ||
				identifier.startsWith("ttr") ||
				identifier.startsWith("tc1vs") ||
				identifier == "qbert" ||
				identifier == "quartz"
		}
		val isPelotonBuild = Build.FINGERPRINT.startsWith(
			"Peloton/",
			ignoreCase = true,
		)

		return mapOf(
			"isPeloton" to (isPelotonBrand || isPelotonModel || isPelotonBuild),
			"brand" to Build.BRAND,
			"manufacturer" to Build.MANUFACTURER,
			"model" to Build.MODEL,
			"product" to Build.PRODUCT,
			"device" to Build.DEVICE,
			"fingerprint" to Build.FINGERPRINT,
			"androidSdk" to Build.VERSION.SDK_INT,
		)
	}

	private fun isIgnoringBatteryOptimizations(): Boolean {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
			return true
		}

		val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
		return powerManager.isIgnoringBatteryOptimizations(packageName)
	}

	private fun requestIgnoreBatteryOptimizations() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isIgnoringBatteryOptimizations()) {
			return
		}

		val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
			data = Uri.parse("package:$packageName")
		}
		startActivity(intent)
	}
}

package com.example.ss2kconfigapp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val powerChannelName = "com.example.ss2kconfigapp/power"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

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

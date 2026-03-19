package com.example.app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_SETTINGS_CHANNEL = "edu_sst/device_settings"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_SETTINGS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> result.success(openNotificationSettings())
                "openAppSettings" -> result.success(openAppSettings())
                "openAutoStartSettings" -> result.success(openAutoStartSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openAppSettings(): Boolean {
        return tryOpenBatteryAndBackgroundSettings() || tryOpenAutoStartSettings() || try {
            startIntent(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openAutoStartSettings(): Boolean {
        return tryOpenAutoStartSettings() || try {
            startIntent(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                }
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun tryOpenBatteryAndBackgroundSettings(): Boolean {
        // Intentos Android estandar para bateria / optimizacion
        val packageUri = Uri.parse("package:$packageName")
        val standardIntents = listOf(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = packageUri
            },
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
        )

        for (intent in standardIntents) {
            if (startIntentIfAvailable(intent)) return true
        }

        return false
    }

    private fun tryOpenAutoStartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER?.lowercase() ?: ""
        val intents = mutableListOf<Intent>()

        if (manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco")) {
            intents += Intent().apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            }
            intents += Intent().apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
                )
                putExtra("package_name", packageName)
                putExtra("package_label", applicationInfo.loadLabel(packageManager).toString())
            }
        }
        if (manufacturer.contains("oppo") || manufacturer.contains("oneplus") || manufacturer.contains("realme")) {
            intents += Intent().apply {
                component = ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            }
            intents += Intent().apply {
                component = ComponentName(
                    "com.oplus.safecenter",
                    "com.oplus.safecenter.startupapp.StartupAppListActivity"
                )
            }
        }
        if (manufacturer.contains("vivo")) {
            intents += Intent().apply {
                component = ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"
                )
            }
            intents += Intent().apply {
                component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            }
        }
        if (manufacturer.contains("huawei") || manufacturer.contains("honor")) {
            intents += Intent().apply {
                component = ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            }
        }
        if (manufacturer.contains("samsung")) {
            intents += Intent("com.samsung.android.sm.ACTION_BATTERY").apply {
                putExtra("package_name", packageName)
            }
        }

        for (intent in intents) {
            if (startIntentIfAvailable(intent)) return true
        }
        return false
    }

    private fun startIntentIfAvailable(intent: Intent): Boolean {
        return try {
            if (intent.resolveActivity(packageManager) != null) {
                startIntent(intent)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun startIntent(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}

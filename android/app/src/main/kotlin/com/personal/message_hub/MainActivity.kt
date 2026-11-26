package com.personal.message_hub

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "message_hub/native")
            .setMethodCallHandler { call, result ->
                fun background(work: () -> Any?) {
                    io.execute {
                        try {
                            val value = work()
                            main.post { result.success(value) }
                        } catch (e: SecurityException) {
                            main.post { result.error("permission", e.message, null) }
                        } catch (e: Exception) {
                            main.post { result.error("failed", e.message, null) }
                        }
                    }
                }
                val since = (call.argument<Number>("sinceMs") ?: 0).toLong()
                when (call.method) {
                    "readSms" -> background { SmsReader(applicationContext).read(since) }
                    "waNotifications" -> background { NotificationStore(applicationContext).since(since) }
                    "clearWaNotifications" -> background { NotificationStore(applicationContext).clear(); null }
                    "keepScreenOn" -> {
                        // Android cuts network for apps once the screen turns off; long scans need it on.
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "notificationAccessGranted" -> result.success(notificationAccessGranted())
                    "openNotificationAccessSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun notificationAccessGranted(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(":").any { ComponentName.unflattenFromString(it)?.packageName == packageName }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                ComponentName(this, WhatsAppNotificationListener::class.java).flattenToString(),
            )
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }
}

package moe.rinn.mychu

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

/** Upgrade-only cleanup. Never publishes notifications or schedules new work. */
internal object RetiredLiveNotificationCleanup {
    fun run(context: Context) {
        val marker = context.getSharedPreferences("retired_features", Context.MODE_PRIVATE)
        if (marker.getBoolean("android_live_notifications_removed_v1", false)) return
        val oldStore = context.getSharedPreferences("mychu_live_updates", Context.MODE_PRIVATE)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        // Match the old PendingIntent identity without keeping the removed receiver class.
        for (key in oldStore.all.keys.filter { it.startsWith("account.") }) {
            val accountKey = key.removePrefix("account.")
            for (index in 0 until 64) {
                val intent = Intent("moe.rinn.mychu.action.LIVE_UPDATE_REFRESH").apply {
                    component = ComponentName(context.packageName, "moe.rinn.mychu.LiveUpdateAlarmReceiver")
                }
                val pending = PendingIntent.getBroadcast(context,
                    480100 + accountKey.hashCode() * 31 + index, intent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                if (pending != null) {
                    alarmManager.cancel(pending)
                    pending.cancel()
                }
            }
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(480001)
        manager.cancel(480002)
        manager.cancel("VIVO_SUPERX_TAG", 480003)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.deleteNotificationChannel("mychu_live_course")
            manager.deleteNotificationChannel("mychu_vivo_superx_demo")
        }
        check(oldStore.edit().clear().commit())
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val editor = flutterPrefs.edit()
        for (key in flutterPrefs.all.keys) {
            if (key.startsWith("flutter.preferences.v1.live_update.") ||
                key.startsWith("flutter.live_update.")) editor.remove(key)
        }
        check(editor.commit())
        check(marker.edit().putBoolean("android_live_notifications_removed_v1", true).commit())
    }
}

package moe.rinn.mychu.desktopwidgets

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Runs Glance refresh requests inside the process that owns widget sessions. */
internal class DesktopWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(ACTION_REFRESH, Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return

        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                refreshMutex.withLock {
                    val appContext = context.applicationContext
                    try {
                        TodayScheduleWidget().updateAll(appContext)
                    } finally {
                        try {
                            WeekScheduleWidget().updateAll(appContext)
                        } finally {
                            DesktopWidgetScheduler.schedule(appContext)
                        }
                    }
                }
            } catch (_: Exception) {
                // The widget refresh is best-effort; the next snapshot retries it.
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        const val ACTION_REFRESH = "moe.rinn.mychu.action.REFRESH_DESKTOP_WIDGETS"
        private val refreshMutex = Mutex()
    }
}

package moe.rinn.mychu.desktopwidgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import java.time.Instant
import java.time.ZoneOffset

/** Both providers reconcile the same boundary from the same local snapshot. */
internal object DesktopWidgetScheduler {
    fun schedule(context: Context, now: Instant = Instant.now()) {
        val manager = AppWidgetManager.getInstance(context)
        val hasToday = manager.getAppWidgetIds(ComponentName(context, TodayScheduleWidgetReceiver::class.java)).isNotEmpty()
        val hasWeek = manager.getAppWidgetIds(ComponentName(context, WeekScheduleWidgetReceiver::class.java)).isNotEmpty()
        val alarms = context.getSystemService(AlarmManager::class.java)
        val operation = PendingIntent.getBroadcast(
            context, 460201,
            Intent(context, DesktopWidgetRefreshReceiver::class.java).setAction(DesktopWidgetRefreshReceiver.ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarms.cancel(operation)
        if (!hasToday && !hasWeek) return
        val today = WidgetSnapshotStore(context).readToday(now)
        if (today.status != TodayScheduleStatus.READY) return
        val midnight = today.businessDate.plusDays(1).atStartOfDay().toInstant(ZoneOffset.ofHours(8))
        val next = nextRefresh(now, midnight, if (hasToday) today.courses.mapNotNull { it.endAt } else emptyList())
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        if (exact) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.toEpochMilli(), operation)
        else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.toEpochMilli(), operation)
    }

    fun nextRefresh(now: Instant, midnight: Instant, courseEnds: List<Instant>): Instant =
        minOf(midnight, courseEnds.filter { it.isAfter(now) }.minOrNull() ?: midnight)
}

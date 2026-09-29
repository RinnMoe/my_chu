package moe.rinn.mychu

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object ScheduledAlertScheduler {
    fun replace(
        context: Context,
        accountKey: String,
        providerId: String,
        alerts: List<ScheduledAlert>,
    ) {
        val previous = ScheduledAlertStore.readAll(context)
        previous.forEach { cancel(context, it) }
        val now = System.currentTimeMillis()
        val bounded = (previous.filterNot {
            it.accountKey == accountKey && it.providerId == providerId
        } + alerts)
            .filter { it.triggerAt > now && it.validUntil >= now }
            .distinctBy { "${it.accountKey}|${it.key}" }
            .sortedBy { it.triggerAt }
            .take(ScheduledAlertStore.MAX_SCHEDULED_ALERTS)
        ScheduledAlertStore.replaceAll(context, bounded)
        bounded.forEach { schedule(context, it) }
    }

    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        ScheduledAlertStore.readAll(context)
            .filter { it.triggerAt > now && it.validUntil >= now }
            .forEach { schedule(context, it) }
    }

    fun cancelProvider(context: Context, accountKey: String, providerId: String) {
        ScheduledAlertStore.readProvider(context, accountKey, providerId).forEach {
            cancel(context, it)
        }
        ScheduledAlertStore.clearProvider(context, accountKey, providerId)
    }

    fun clearAll(context: Context) {
        ScheduledAlertStore.readAll(context).forEach {
            cancel(context, it)
            ScheduledAlertNotifier.cancel(context, it)
        }
        ScheduledAlertStore.clearAll(context)
    }

    private fun cancel(context: Context, alert: ScheduledAlert) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context, alert))
    }

    private fun schedule(context: Context, alert: ScheduledAlert) {
        if (alert.triggerAt <= System.currentTimeMillis()) return
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = pendingIntent(context, alert)
        val authorized = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            manager.canScheduleExactAlarms()
        val mode = ScheduledAlertModeResolver.resolve(
            requested = ScheduledAlertStore.exactRequested(context),
            authorized = authorized,
        )
        if (mode == ScheduledAlertAlarmMode.EXACT) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alert.triggerAt, operation)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alert.triggerAt, operation)
        }
    }

    private fun pendingIntent(context: Context, alert: ScheduledAlert): PendingIntent {
        val intent = Intent(context, ScheduledAlertReceiver::class.java).apply {
            action = ScheduledAlertReceiver.ACTION_DELIVER
            putExtra(ScheduledAlertReceiver.EXTRA_ACCOUNT, alert.accountKey)
            putExtra(ScheduledAlertReceiver.EXTRA_PROVIDER, alert.providerId)
            putExtra(ScheduledAlertReceiver.EXTRA_EVENT, alert.eventId)
            putExtra(ScheduledAlertReceiver.EXTRA_TRIGGER, alert.triggerAt)
        }
        return PendingIntent.getBroadcast(
            context,
            alert.key.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

enum class ScheduledAlertAlarmMode { EXACT, INEXACT }

object ScheduledAlertModeResolver {
    fun resolve(requested: Boolean, authorized: Boolean): ScheduledAlertAlarmMode =
        if (requested && authorized) ScheduledAlertAlarmMode.EXACT
        else ScheduledAlertAlarmMode.INEXACT
}

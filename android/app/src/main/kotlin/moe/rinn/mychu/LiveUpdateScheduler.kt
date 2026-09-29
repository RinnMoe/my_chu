package moe.rinn.mychu

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/** Schedules one-shot inexact boundary alarms from a stored Live Update package. */
object LiveUpdateScheduler {
    private const val MAX_ALARMS = 64
    private const val PROGRESS_INTERVAL_MILLIS = 5 * 60 * 1000L

    private data class AlarmSpec(val at: Long, val progressCheckpoint: Boolean)

    fun schedule(context: Context, liveUpdate: LiveUpdatePackage) {
        if (liveUpdate.isDemo) return
        cancel(context, liveUpdate)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val now = System.currentTimeMillis()
        val specs = liveUpdate.boundaries
            .asSequence()
            .filter { it.at > now }
            .map { AlarmSpec(it.at, progressCheckpoint = false) }
            .toMutableList()

        // ProgressStyle does not advance by itself. While the effective
        // render is active, add bounded five-minute local checkpoints. These
        // alarms only reread the persisted package; they never start Flutter
        // or make a network request.
        val effectiveBoundary = liveUpdate.boundaries
            .filter { it.at <= now }
            .maxByOrNull { it.at }
        val effectiveRender = when {
            effectiveBoundary?.cancel == true -> null
            effectiveBoundary != null -> effectiveBoundary.render
            else -> liveUpdate.render
        }
        if (effectiveRender?.phase == "active") {
            val start = effectiveRender.startAt?.let(::parseLiveUpdateEpochMillis)
            val end = effectiveRender.endAt?.let(::parseLiveUpdateEpochMillis)
            if (start != null && end != null && end > now) {
                var checkpoint = now + PROGRESS_INTERVAL_MILLIS
                while (checkpoint < end && specs.size < MAX_ALARMS) {
                    if (checkpoint >= start) {
                        specs += AlarmSpec(checkpoint, progressCheckpoint = true)
                    }
                    checkpoint += PROGRESS_INTERVAL_MILLIS
                }
            }
        }

        // Keep all boundary transitions before checkpoint slots so the end
        // cancellation can never be crowded out by a long course window.
        val selected = specs
            .sortedWith(compareBy<AlarmSpec> { it.progressCheckpoint }.thenBy { it.at })
            .take(MAX_ALARMS)
        for ((index, spec) in selected.withIndex()) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                spec.at,
                pendingIntent(context, liveUpdate, index, spec.progressCheckpoint),
            )
        }
    }

    fun cancel(context: Context, liveUpdate: LiveUpdatePackage) {
        if (liveUpdate.isDemo) return
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        for (index in 0 until MAX_ALARMS) {
            alarmManager.cancel(pendingIntent(context, liveUpdate, index, false))
            alarmManager.cancel(pendingIntent(context, liveUpdate, index, true))
        }
    }

    fun rescheduleAll(context: Context) {
        for (liveUpdate in LiveUpdateStore.readAllFormal(context)) {
            schedule(context, liveUpdate)
        }
    }

    private fun pendingIntent(
        context: Context,
        liveUpdate: LiveUpdatePackage,
        index: Int,
        progressCheckpoint: Boolean,
    ): PendingIntent {
        val intent = Intent(context, LiveUpdateAlarmReceiver::class.java).apply {
            action = LiveUpdateAlarmReceiver.ACTION_REFRESH
            putExtra(LiveUpdateAlarmReceiver.EXTRA_ACCOUNT_KEY, liveUpdate.accountKey)
            putExtra(LiveUpdateAlarmReceiver.EXTRA_IS_DEMO, liveUpdate.isDemo)
            putExtra(LiveUpdateAlarmReceiver.EXTRA_PROGRESS_CHECKPOINT, progressCheckpoint)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(
            context,
            480100 + liveUpdate.accountKey.hashCode() * 31 + index,
            intent,
            flags,
        )
    }
}

package moe.rinn.mychu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Rebuilds only persisted host surfaces after wall-clock changes. */
class TemporalRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_TIME_CHANGED &&
            intent.action != Intent.ACTION_TIMEZONE_CHANGED
        ) return
        recover(context)
    }

    companion object {
        fun recover(context: Context) {
            val now = System.currentTimeMillis()
            // Reconcile the visible notification immediately after a wall-clock
            // change.  ProgressStyle is a static value; waiting for the next
            // checkpoint would leave an active course at its pre-change
            // position until then.
            for (liveUpdate in LiveUpdateStore.readAllFormal(context)) {
                val boundary = liveUpdate.boundaries
                    .filter { it.at <= now }
                    .maxByOrNull { it.at }
                if (boundary?.cancel == true) {
                    LiveUpdateNotifier.cancel(context, liveUpdate)
                } else if (boundary != null || liveUpdate.postImmediately) {
                    LiveUpdateNotifier.post(
                        context,
                        liveUpdate,
                        boundary?.render ?: liveUpdate.render,
                    )
                }
            }
            LiveUpdateScheduler.rescheduleAll(context)
            ScheduledAlertScheduler.rescheduleAll(context)
        }
    }
}

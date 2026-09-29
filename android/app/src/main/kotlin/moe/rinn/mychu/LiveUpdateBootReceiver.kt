package moe.rinn.mychu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveUpdateBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        for (liveUpdate in LiveUpdateStore.readAllFormal(context)) {
            val now = System.currentTimeMillis()
            val boundary = liveUpdate.boundaries
                .filter { it.at <= now }
                .maxByOrNull { it.at }
            if (boundary?.cancel == true) {
                LiveUpdateNotifier.cancel(context, liveUpdate)
                continue
            }
            if (boundary != null || liveUpdate.postImmediately) {
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

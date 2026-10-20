package moe.rinn.mychu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restores persisted reminders without starting Flutter or accessing the network. */
class TemporalRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_TIME_CHANGED &&
            intent.action != Intent.ACTION_TIMEZONE_CHANGED &&
            intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
        ) return
        recover(context)
    }

    companion object {
        // The ongoing course activity has its own recovery receiver; wiring it
        // here as well would run the same re-coordination twice per broadcast.
        fun recover(context: Context) {
            TimeReminderEngine.reschedule(context)
        }
    }
}

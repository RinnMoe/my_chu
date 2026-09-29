package moe.rinn.mychu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScheduledAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DELIVER) return
        val account = intent.getStringExtra(EXTRA_ACCOUNT).orEmpty()
        val provider = intent.getStringExtra(EXTRA_PROVIDER).orEmpty()
        val event = intent.getStringExtra(EXTRA_EVENT).orEmpty()
        val trigger = intent.getLongExtra(EXTRA_TRIGGER, -1)
        val alert = ScheduledAlertStore.readProvider(context, account, provider)
            .firstOrNull { it.eventId == event && it.triggerAt == trigger }
            ?: return
        if (System.currentTimeMillis() <= alert.validUntil) {
            if (ScheduledAlertNotifier.post(context, alert)) {
                ScheduledAlertStore.addReceipt(context, alert)
            }
        }
        ScheduledAlertStore.remove(context, alert)
    }

    companion object {
        const val ACTION_DELIVER = "moe.rinn.mychu.action.SCHEDULED_ALERT_DELIVER"
        const val EXTRA_ACCOUNT = "scheduled_alert_account"
        const val EXTRA_PROVIDER = "scheduled_alert_provider"
        const val EXTRA_EVENT = "scheduled_alert_event"
        const val EXTRA_TRIGGER = "scheduled_alert_trigger"
    }
}

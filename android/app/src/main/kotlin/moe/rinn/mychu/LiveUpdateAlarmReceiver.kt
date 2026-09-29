package moe.rinn.mychu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveUpdateAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH -> refresh(context, intent)
            ACTION_DISMISS -> dismiss(context, intent)
        }
    }

    private fun refresh(context: Context, intent: Intent) {
        val isDemo = intent.getBooleanExtra(EXTRA_IS_DEMO, false)
        val accountKey = intent.getStringExtra(EXTRA_ACCOUNT_KEY).orEmpty()
        val key = if (isDemo) LiveUpdateStore.DEMO_KEY else LiveUpdateStore.keyForAccount(accountKey)
        val liveUpdate = LiveUpdateStore.read(context, key) ?: return

        val now = System.currentTimeMillis()
        val progressCheckpoint = intent.getBooleanExtra(EXTRA_PROGRESS_CHECKPOINT, false)
        val boundary = liveUpdate.boundaries
            .filter { it.at <= now }
            .maxByOrNull { it.at }
        if (boundary?.cancel == true) {
            LiveUpdateNotifier.cancel(context, liveUpdate)
            LiveUpdateScheduler.schedule(context, liveUpdate)
            return
        }
        if (progressCheckpoint) {
            // A checkpoint must use the effective active render (usually the
            // start boundary) so the notifier can recompute progress from the
            // persisted start/end timestamps.
            if (boundary?.render?.phase == "active" || liveUpdate.render.phase == "active") {
                LiveUpdateNotifier.post(
                    context,
                    liveUpdate,
                    boundary?.render?.takeIf { it.phase == "active" } ?: liveUpdate.render,
                )
            }
        } else if (boundary != null || liveUpdate.postImmediately) {
            LiveUpdateNotifier.post(
                context,
                liveUpdate,
                boundary?.render ?: liveUpdate.render,
            )
        }
        LiveUpdateScheduler.schedule(context, liveUpdate)
    }

    private fun dismiss(context: Context, intent: Intent) {
        val isDemo = intent.getBooleanExtra(EXTRA_IS_DEMO, false)
        val accountKey = intent.getStringExtra(EXTRA_ACCOUNT_KEY).orEmpty()
        val key = if (isDemo) LiveUpdateStore.DEMO_KEY else LiveUpdateStore.keyForAccount(accountKey)
        val liveUpdate = LiveUpdateStore.read(context, key) ?: run {
            LiveUpdateNotifier.cancelKnown(context)
            return
        }
        LiveUpdateStore.markDismissed(context, liveUpdate)
        LiveUpdateStore.delete(context, key)
        LiveUpdateNotifier.cancel(context, liveUpdate)
        LiveUpdateScheduler.cancel(context, liveUpdate)
    }

    companion object {
        const val ACTION_REFRESH = "moe.rinn.mychu.action.LIVE_UPDATE_REFRESH"
        const val ACTION_DISMISS = "moe.rinn.mychu.action.LIVE_UPDATE_DISMISS"
        const val EXTRA_ACCOUNT_KEY = "mychu_live_update_account"
        const val EXTRA_IS_DEMO = "mychu_live_update_demo"
        const val EXTRA_PROGRESS_CHECKPOINT = "mychu_live_update_progress_checkpoint"
    }
}

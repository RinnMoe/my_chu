package moe.rinn.mychu.courselive

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import org.json.JSONObject

/**
 * Native coordinator for the pre-class and ongoing course activity.
 *
 * It persists a minimal plan, derives the visible stage from real time, renders
 * at most one ongoing notification and re-arms a single exact alarm for the next
 * phase boundary and a separate non-exact progress checkpoint. It never starts a Flutter engine, never touches
 * the campus network and never holds an account or a credential.
 */
object CourseLiveEngine {
    private const val ACTION_ALARM = "moe.rinn.mychu.action.COURSE_LIVE_ALARM"

    private fun currentTime(): Long = System.currentTimeMillis()

    private var memoryOwner: String? = null
    private var memoryGeneration: Long = 0
    private var memoryBlocks: List<CourseLiveBlock> = emptyList()
    private var memoryDismissals: Map<String, Long> = emptyMap()
    private var memoryShown: String? = null

    // ------------------------------------------------------------------ plan

    /**
     * Binds a new ownership lineage and stores the plan. A different owner or
     * generation always invalidates whatever was displayed before.
     */
    @Synchronized
    fun activate(context: Context, owner: String): Long {
        val store = CourseLiveStore(context)
        val previous = store.bound()?.owner
        val generation = store.activate(owner)
        // The previous lineage's occurrence must never enter the incoming
        // account's dismissal ledger, or the same course would be suppressed
        // for the new account as well.
        endDisplay(context, dismissOccurrence = false)
        memoryOwner = owner
        memoryGeneration = generation
        memoryBlocks = emptyList()
        memoryDismissals = store.ledger()
        memoryShown = null
        if (previous != null && previous != owner) {
            store.forgetDisplay()
        }
        return generation
    }

    @Synchronized
    fun deactivate(context: Context) {
        clearDisplay(context)
        cancelAlarm(context)
        CourseLiveStore(context).deactivate()
        memoryOwner = null
        memoryGeneration = 0
        memoryBlocks = emptyList()
        memoryDismissals = emptyMap()
        memoryShown = null
    }

    @Synchronized
    fun replacePlan(
        context: Context,
        owner: String,
        generation: Long,
        payload: JSONObject,
    ) {
        val store = CourseLiveStore(context)
        if (!store.matches(owner, generation)) return
        val plan = CourseLivePlan.fromRaw(payload) ?: return
        if (plan.owner != owner || plan.generation != generation) return
        store.writePlan(payload)
        memoryOwner = owner
        memoryGeneration = generation
        memoryBlocks = plan.blocks
        memoryDismissals = store.ledger()
        memoryShown = store.rememberedDisplay()?.first
        // A replacement plan must not leave a previous occurrence on screen.
        if (memoryShown != null && memoryBlocks.none { it.eventId == memoryShown }) {
            endDisplay(context)
            memoryShown = null
        }
        coordinate(context)
    }

    /**
     * Confirmed empty projection. Only this path revokes the plan; an
     * unavailable or expired source keeps the unexpired native plan.
     */
    @Synchronized
    fun clearPlan(context: Context, owner: String, generation: Long) {
        val store = CourseLiveStore(context)
        if (!store.matches(owner, generation)) return
        store.clearPlan()
        memoryBlocks = emptyList()
        memoryShown = null
        endDisplay(context)
        cancelAlarm(context)
    }

    /** Re-coordinates from persisted state. Used by every local trigger. */
    @Synchronized
    fun reschedule(context: Context) {
        val store = CourseLiveStore(context)
        val bound = store.bound()
        if (bound == null) {
            clearDisplay(context)
            cancelAlarm(context)
            return
        }
        val plan = store.readPlan()
        memoryOwner = bound.owner
        memoryGeneration = bound.generation
        memoryBlocks = plan?.blocks ?: emptyList()
        memoryDismissals = store.ledger()
        memoryShown = store.rememberedDisplay()?.first
        coordinate(context)
    }

    // ------------------------------------------------------------- dismissal

    /**
     * Manual "结束本次显示". The dismissal is persisted before the instance is
     * removed, so a later broadcast, a reopened app or a reboot cannot bring
     * the same occurrence back.
     *
     * [dismissOccurrence] is false when this call only clears a previous
     * ownership lineage or an occurrence that is no longer part of the plan.
     */
    @Synchronized
    fun endDisplay(
        context: Context,
        eventId: String? = null,
        now: Long = currentTime(),
        dismissOccurrence: Boolean = true,
    ) {
        val store = CourseLiveStore(context)
        val owner = memoryOwner
        val resolved = eventId ?: memoryShown
        if (dismissOccurrence && owner != null && !resolved.isNullOrBlank()) {
            store.dismiss(resolved, CourseLiveCoordinator.dismissUntil(now))
            memoryDismissals = store.ledger()
        }
        endNotification(context)
        memoryShown = null
        store.forgetDisplay()
    }

    @Synchronized
    fun handleEndDisplay(context: Context, owner: String?, eventId: String?, now: Long) {
        if (owner == null || eventId.isNullOrBlank()) return
        val store = CourseLiveStore(context)
        val bound = store.bound() ?: return
        if (bound.owner != owner || store.rememberedDisplay()?.first != eventId) return
        // The notification action can start a killed process: the in-memory
        // session is empty then, so reload the persisted one before recording
        // the dismissal and scheduling the next boundary.
        val plan = store.readPlan()
        memoryOwner = bound.owner
        memoryGeneration = bound.generation
        memoryBlocks = plan?.blocks ?: emptyList()
        memoryDismissals = store.ledger()
        memoryShown = store.rememberedDisplay()?.first ?: eventId
        endDisplay(context, eventId, now)
        coordinate(context)
    }

    /**
     * The user swiped the ongoing entry away. Only a user dismissal fires the
     * delete intent, so this is recorded exactly like "结束本次显示"; the
     * system timeout and a programmatic cancel never reach here.
     */
    @Synchronized
    fun handleDismissed(context: Context, owner: String?, eventId: String?, now: Long) {
        if (owner == null || eventId.isNullOrBlank()) return
        val store = CourseLiveStore(context)
        val bound = store.bound() ?: return
        if (bound.owner != owner || store.rememberedDisplay()?.first != eventId) return
        val block = store.readPlan()?.blocks?.firstOrNull { it.eventId == eventId } ?: return
        // A timeout delivered as a delete callback must not become a user dismissal.
        if (now < block.endAt) store.dismiss(eventId, CourseLiveCoordinator.dismissUntil(now))
        // Reload persisted state too: a delete intent can start a cold process.
        reschedule(context)
    }

    /** Owner currently bound in native storage, or null. */
    fun activatedOwner(context: Context): String? = CourseLiveStore(context).bound()?.owner

    /**
     * The persisted plan exactly as it was stored, as a JSON string.
     *
     * Native persistence uses JSONObject/JSONArray rather than codec-compatible
     * Map/List values. Pass JSON text and let the shared layer decode it.
     */
    fun plannedPayload(context: Context): String? =
        CourseLiveStore(context).rawPlan()

    // ---------------------------------------------------------------- queries

    fun validateLaunch(
        context: Context,
        owner: String?,
        generation: Long,
        eventId: String?,
        now: Long,
    ): Boolean {
        if (owner == null || eventId.isNullOrBlank()) return false
        val store = CourseLiveStore(context)
        if (!store.matches(owner, generation)) return false
        val plan = store.readPlan() ?: return false
        val block = plan.blocks.firstOrNull { it.eventId == eventId } ?: return false
        if (now < block.windowStart || now >= block.endAt) return false
        return store.rememberedDisplay()?.first == eventId
    }

    fun status(context: Context): Map<String, Any?> {
        val renderer = CourseLiveAndroidRenderer(context.applicationContext)
        return mapOf(
            "notifications" to (renderer.notificationsAllowed() && renderer.channelEnabled()),
            "exact" to renderer.exactAllowed(),
            "promoted" to renderer.promoted(),
        )
    }

    fun notificationsAllowed(context: Context): Boolean =
        CourseLiveAndroidRenderer(context.applicationContext).notificationsAllowed()

    fun exactAllowed(context: Context): Boolean =
        CourseLiveAndroidRenderer(context.applicationContext).exactAllowed()

    fun alarmAction(): String = ACTION_ALARM

    // -------------------------------------------------------------- internals

    private fun coordinate(context: Context) {
        val renderer = CourseLiveAndroidRenderer(context.applicationContext)
        val session = CourseLiveSession(
            owner = memoryOwner,
            generation = memoryGeneration,
            blocks = memoryBlocks,
            dismissedUntil = memoryDismissals,
            shownEventId = memoryShown,
        )
        val canPost = renderer.notificationsAllowed() && renderer.channelEnabled()
        val effect = CourseLiveCoordinator.coordinate(
            session = session,
            now = currentTime(),
            canPost = canPost,
        )
        apply(context, effect)
    }

    private fun apply(context: Context, effect: CourseLiveEffect) {
        val store = CourseLiveStore(context)
        val renderer = CourseLiveAndroidRenderer(context.applicationContext)
        if (effect.prunedDismissals) {
            store.pruneLedger(currentTime())
            memoryDismissals = store.ledger()
        }
        if (effect.endFirst || effect.cancelDisplay) {
            endNotification(context)
        }
        val post = effect.post
        if (post != null) {
            if (renderer.render(post)) {
                store.rememberDisplay(post.eventId, currentTime())
                memoryShown = post.eventId
            } else {
                renderer.end()
                store.forgetDisplay()
                memoryShown = null
            }
        } else if (effect.forgetDisplay && memoryShown != null) {
            store.forgetDisplay()
            memoryShown = null
        }
        if (effect.nextBoundaryAt != null) {
            arm(context, memoryOwner, effect, currentTime())
        } else {
            cancelAlarm(context)
        }
    }

    private fun endNotification(context: Context) {
        CourseLiveAndroidRenderer(context.applicationContext).end()
    }

    /** Removes any rendered instance and forgets the remembered occurrence. */
    private fun clearDisplay(context: Context) {
        endNotification(context)
        memoryShown = null
        CourseLiveStore(context).forgetDisplay()
    }

    /** Schedules exact stage boundaries and a separate non-exact progress checkpoint. */
    private fun arm(
        context: Context,
        owner: String?,
        effect: CourseLiveEffect,
        now: Long,
    ) {
        if (owner == null) return
        val app = context.applicationContext
        if (!exactAllowed(app) || !notificationsAllowed(app)) {
            cancelAlarm(app)
            return
        }
        val alarmManager = app.getSystemService(AlarmManager::class.java) ?: return
        val boundary = effect.nextBoundaryAt
        if (boundary != null && boundary > now) {
            val pending = PendingIntent.getBroadcast(
                app,
                CourseLiveNotificationIdentity.ALARM_REQUEST,
                alarmIntent(app, owner, CourseLiveNotificationIdentity.ALARM_BOUNDARY),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pending)
            runCatching {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    boundary,
                    pending,
                )
            }
        } else {
            cancelSlot(
                app,
                owner,
                CourseLiveNotificationIdentity.ALARM_BOUNDARY,
                CourseLiveNotificationIdentity.ALARM_REQUEST,
            )
        }
        val checkpoint = effect.nextCheckpointAt
        if (checkpoint != null && checkpoint > now) {
            val pending = PendingIntent.getBroadcast(
                app, CourseLiveNotificationIdentity.CHECKPOINT_REQUEST,
                alarmIntent(app, owner, CourseLiveNotificationIdentity.ALARM_CHECKPOINT),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pending)
            // Progress is best-effort and must not consume the allow-while-idle
            // quota needed by exact course boundaries. Resume will catch up.
            alarmManager.set(AlarmManager.RTC, checkpoint, pending)
        } else {
            cancelSlot(app, owner, CourseLiveNotificationIdentity.ALARM_CHECKPOINT,
                CourseLiveNotificationIdentity.CHECKPOINT_REQUEST)
        }
    }

    /** Cancels every wake-up this feature may have scheduled. */
    private fun cancelAlarm(context: Context) {
        val app = context.applicationContext
        val owner = CourseLiveStore(app).bound()?.owner
            ?: memoryOwner
            ?: return
        cancelSlot(
            app,
            owner,
            CourseLiveNotificationIdentity.ALARM_BOUNDARY,
            CourseLiveNotificationIdentity.ALARM_REQUEST,
        )
        cancelSlot(
            app,
            owner,
            CourseLiveNotificationIdentity.ALARM_CHECKPOINT,
            CourseLiveNotificationIdentity.CHECKPOINT_REQUEST,
        )
    }

    /**
     * Cancels one slot. The intent data depends only on the owner and the slot,
     * never on the generation, because a PendingIntent is identified by action +
     * data + class: a generation-dependent data URI would make each generation a
     * different request and the cancellation would never match.
     */
    private fun cancelSlot(
        app: Context,
        owner: String,
        slot: String,
        requestCode: Int,
    ) {
        val pending = PendingIntent.getBroadcast(
            app,
            requestCode,
            alarmIntent(app, owner, slot),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        app.getSystemService(AlarmManager::class.java)?.cancel(pending)
        pending.cancel()
    }

    private fun alarmIntent(context: Context, owner: String, slot: String): Intent =
        Intent(context, CourseLiveReceiver::class.java)
            .setAction(ACTION_ALARM)
            .setData(
                Uri.Builder()
                    .scheme("mychu-course-live-alarm")
                    .authority(owner)
                    .appendPath(slot)
                    .build(),
            )
            .putExtra("courseLiveOwner", owner)


}

/** Handles the pre-class boundary alarm and the manual "结束本次显示" action. */
class CourseLiveReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            CourseLiveEngine.alarmAction() -> CourseLiveEngine.reschedule(app)
            ACTION_END_DISPLAY -> CourseLiveEngine.handleEndDisplay(
                app,
                intent.getStringExtra("courseLiveOwner"),
                intent.getStringExtra("courseLiveEvent"),
                System.currentTimeMillis(),
            )
            // Delivered by the system only when the user removes the entry.
            ACTION_DISMISSED -> CourseLiveEngine.handleDismissed(
                app,
                intent.getStringExtra("courseLiveOwner"),
                intent.getStringExtra("courseLiveEvent"),
                System.currentTimeMillis(),
            )
        }
    }

    companion object {
        const val ACTION_END_DISPLAY = "moe.rinn.mychu.action.COURSE_LIVE_END_DISPLAY"
        const val ACTION_DISMISSED = "moe.rinn.mychu.action.COURSE_LIVE_DISMISSED"
    }
}

/**
 * System re-coordination for boot, clock/timezone/date changes, app updates and
 * exact-alarm permission changes. Never starts Flutter and never fetches data.
 */
class CourseLiveRecoveryReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> CourseLiveEngine.reschedule(app)
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            -> CourseLiveEngine.reschedule(app)
            Intent.ACTION_MY_PACKAGE_REPLACED -> CourseLiveEngine.reschedule(app)
            ACTION_EXACT_ALARM_PERMISSION_CHANGED ->
                CourseLiveEngine.reschedule(app)
        }
    }

    companion object {
        const val ACTION_EXACT_ALARM_PERMISSION_CHANGED =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
    }
}

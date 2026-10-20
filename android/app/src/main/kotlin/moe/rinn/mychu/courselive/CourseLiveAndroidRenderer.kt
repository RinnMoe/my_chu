package moe.rinn.mychu.courselive

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import moe.rinn.mychu.MainActivity
import moe.rinn.mychu.R

/** One fixed notification slot, so at most one course is ever displayed.
 *
 * The slot deliberately does not depend on the owner: ownership can change
 * while no Flutter engine is attached, and a per-owner tag would then leave the
 * previous account's notification on the shade. The owner travels inside the
 * plan and the launch extras instead. */
object CourseLiveNotificationIdentity {
    const val TAG = "mychu-course-live"
    const val NOTIFICATION_ID = 470301
    const val ALARM_REQUEST = 470302
    const val CONTENT_REQUEST = 470303
    const val END_REQUEST = 470304
    const val DISMISS_REQUEST = 470305
    const val CHECKPOINT_REQUEST = 470306

    /** Independent identity for non-exact progress updates. */
    const val ALARM_BOUNDARY = "boundary"
    const val ALARM_CHECKPOINT = "checkpoint"

    /**
     * `Notification.FLAG_PROMOTED_ONGOING`, inlined so reading the real
     * promotion state needs no API 36.1 metadata at runtime. `javap` on
     * `android-36.1/android.jar` confirms the value is 262144 (1 shl 18).
     */
    const val FLAG_PROMOTED_ONGOING = 262144
    const val CHANNEL_ID = "mychu_course_live_activity"
    const val CHANNEL_NAME = "课程实时动态"
}

/**
 * The standard Android renderer for the pre-class course notification.
 *
 * The notification is a single ongoing entry: updates replace it in place, the
 * channel is silent so an update never rings again, and the timeout is clamped
 * to the current stage so a delayed broadcast cannot leave expired content.
 */
class CourseLiveAndroidRenderer(private val context: Context) {
    private val manager: NotificationManager
        get() = context.getSystemService(NotificationManager::class.java)

    fun notificationsAllowed(): Boolean {
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun exactAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.getSystemService(android.app.AlarmManager::class.java)
                .canScheduleExactAlarms()

    fun channelEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return true
        ensureChannel()
        return manager.getNotificationChannel(CourseLiveNotificationIdentity.CHANNEL_ID)
            ?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        manager.getNotificationChannel(CourseLiveNotificationIdentity.CHANNEL_ID)?.let { existing ->
            existing.description = "显示课前信息与课中进度"
            manager.createNotificationChannel(existing)
            return
        }
        val channel = NotificationChannel(
            CourseLiveNotificationIdentity.CHANNEL_ID,
            CourseLiveNotificationIdentity.CHANNEL_NAME,
            // IMPORTANCE_LOW keeps it ongoing but never rings or vibrates.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "显示课前信息与课中进度"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(channel)
    }

    fun render(notification: CourseLiveNotification): Boolean {
        if (!notificationsAllowed()) return false
        ensureChannel()
        if (!channelEnabled()) return false
        val posted = runCatching { build(notification) }.getOrNull() ?: return false
        return runCatching {
            manager.notify(
                CourseLiveNotificationIdentity.TAG,
                CourseLiveNotificationIdentity.NOTIFICATION_ID,
                posted,
            )
        }.isSuccess
    }

    /** Ends the single slot. There is exactly one tagged entry per package. */
    fun end() {
        runCatching {
            manager.cancel(
                CourseLiveNotificationIdentity.TAG,
                CourseLiveNotificationIdentity.NOTIFICATION_ID,
            )
        }
    }

    /**
     * Whether the system actually promoted this entry to a live update.
     *
     * This reads `FLAG_PROMOTED_ONGOING` on the posted notification, so it
     * reports the real outcome rather than the request: a user who turned live
     * updates off still sees `false` here.
     */
    fun promoted(): Boolean {
        if (!notificationsAllowed()) return false
        if (Build.VERSION.SDK_INT < 36) return false
        return runCatching {
            val active = manager.activeNotifications.firstOrNull {
                it.id == CourseLiveNotificationIdentity.NOTIFICATION_ID
            } ?: return false
            val flags = Notification::class.java.getField("flags")
                .getInt(active.notification)
            (flags and CourseLiveNotificationIdentity.FLAG_PROMOTED_ONGOING) != 0
        }.getOrDefault(false)
    }

    private fun build(notification: CourseLiveNotification): Notification {
        val startTime = SimpleDateFormat("HH:mm", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("GMT+08:00")
        }.format(Date(notification.startAt))
        val title = "$startTime ${notification.name.ifBlank { "课程" }}"
        val body = buildString {
            append(if (notification.phase == CourseLivePhase.ONGOING) "正在上课" else "即将上课")
            if (notification.location.isNotBlank()) {
                append(" · ").append(notification.location)
            }
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CourseLiveNotificationIdentity.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            CourseLiveNotificationIdentity.CONTENT_REQUEST,
            contentTapIntent(notification),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setContentIntent(contentIntent)
            .setDeleteIntent(dismissedPendingIntent(notification))
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, R.drawable.ic_course_live),
                    "结束本次显示",
                    endPendingIntent(notification),
                ).build(),
            )
        if (Build.VERSION.SDK_INT >= 26) {
            val timeout = notification.timeoutMillis.coerceAtLeast(0)
            if (timeout > 0) builder.setTimeoutAfter(timeout)
        }
        if (notification.progress != null) {
            builder.setProgress(100, notification.progress, false)
        }
        requestPromotion(builder)
        return builder.build()
    }

    /**
     * Asks the platform to promote this entry to a live update.
     *
     * API 36.1 opens the current path: an explicit promoted-ongoing request plus
     * `POST_PROMOTED_NOTIFICATIONS`, and no colorized request. The call is made
     * reflectively because the project compiles against the 36.1 platform jar
     * while devices may only have the older minor release; on those the request
     * silently falls back to the colorized characteristics path. Promotion stays
     * the system's decision, and [promoted] reports the real outcome.
     */
    private fun requestPromotion(
        builder: Notification.Builder,
    ) {
        if (Build.VERSION.SDK_INT < 36) return
        val requested = runCatching {
            builder.javaClass
                .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                .invoke(builder, true)
            true
        }.getOrDefault(false)
        if (!requested) {
            // Older minor releases know only the promotable-characteristics path.
            builder.setColorized(true)
        }
        val marker = "🎓"
        runCatching {
            builder.javaClass
                .getMethod("setShortCriticalText", String::class.java)
                .invoke(builder, marker)
        }
    }

    private fun contentTapIntent(notification: CourseLiveNotification): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(MainActivity.ACTION_OPEN_APP)
            .setData(
                Uri.Builder()
                    .scheme("mychu-course-live")
                    .authority(notification.owner)
                    .appendPath(notification.eventId)
                    .build(),
            )
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_TARGET_APP_ID, "feature.academic.schedule")
            .putExtra(
                MainActivity.EXTRA_COURSE_LIVE_OWNER,
                notification.owner,
            )
            .putExtra(
                MainActivity.EXTRA_COURSE_LIVE_GENERATION,
                notification.generation,
            )
            .putExtra(
                MainActivity.EXTRA_COURSE_LIVE_EVENT,
                notification.eventId,
            )
            .putExtra(
                MainActivity.EXTRA_COURSE_LIVE_START,
                notification.startAt,
            )

    private fun endPendingIntent(notification: CourseLiveNotification): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            CourseLiveNotificationIdentity.END_REQUEST,
            Intent(context, CourseLiveReceiver::class.java)
                .setAction(CourseLiveReceiver.ACTION_END_DISPLAY)
                .setData(
                    Uri.Builder()
                        .scheme("mychu-course-live-end")
                        .authority(notification.owner)
                        .appendPath(notification.eventId)
                        .build(),
                )
                .putExtra("courseLiveOwner", notification.owner)
                .putExtra("courseLiveEvent", notification.eventId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * Fired by the system only when the user removes the entry, so a swipe is
     * recorded exactly like "结束本次显示". A system timeout or a programmatic
     * cancel does not fire it.
     */
    private fun dismissedPendingIntent(
        notification: CourseLiveNotification,
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        CourseLiveNotificationIdentity.DISMISS_REQUEST,
        Intent(context, CourseLiveReceiver::class.java)
            .setAction(CourseLiveReceiver.ACTION_DISMISSED)
            .setData(
                Uri.Builder()
                    .scheme("mychu-course-live-dismissed")
                    .authority(notification.owner)
                    .appendPath(notification.eventId)
                    .build(),
            )
            .putExtra("courseLiveOwner", notification.owner)
            .putExtra("courseLiveEvent", notification.eventId),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

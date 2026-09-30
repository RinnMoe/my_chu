package moe.rinn.mychu

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.Settings

object LiveUpdateNotifier {
    const val CHANNEL_ID = "mychu_live_course"
    const val COURSE_NOTIFICATION_ID = 480001
    const val DEMO_NOTIFICATION_ID = 480002

    fun post(context: Context, liveUpdate: LiveUpdatePackage, render: LiveUpdateRender) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(Icon.createWithResource(context, R.mipmap.ic_launcher))
            .setContentTitle(render.title)
            .setContentText(render.body)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(render.ongoing)
            .setAutoCancel(!render.ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent(context, liveUpdate))
            .setDeleteIntent(dismissIntent(context, liveUpdate))

        if (render.countdownAt != null) {
            builder
                .setWhen(render.countdownAt)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }

        if (Build.VERSION.SDK_INT >= 36 && !render.shortCriticalText.isNullOrBlank()) {
            builder.setShortCriticalText(render.shortCriticalText)
        }

        if (Build.VERSION.SDK_INT >= 36 && render.progressMax > 0) {
            val elapsed = progressAtNow(render)
            val remaining = (render.progressMax - elapsed).coerceAtLeast(1)
            val style = Notification.ProgressStyle()
                .setProgress(elapsed)
                .setStyledByProgress(false)
                .setProgressTrackerIcon(
                    render.trackerEmoji
                        ?.takeIf { it.isNotBlank() }
                        ?.let { emojiTrackerIcon(context, it) },
                )
            if (elapsed > 0) {
                style.addProgressSegment(
                    Notification.ProgressStyle.Segment(elapsed)
                        .setColor(Color.rgb(79, 146, 199)),
                )
            }
            style.addProgressSegment(
                Notification.ProgressStyle.Segment(remaining)
                    .setColor(Color.rgb(224, 224, 224)),
            )
            style.addProgressPoint(
                Notification.ProgressStyle.Point(render.progressMax)
                    .setColor(Color.rgb(79, 146, 199)),
            )
            builder.setStyle(style)
        } else if (render.progressMax > 0) {
            builder.setProgress(render.progressMax, progressAtNow(render), false)
        }

        if (render.ongoing && render.requestPromoted && Build.VERSION.SDK_INT_FULL >= 3600001) {
            try {
                if (manager.canPostPromotedNotifications()) {
                    builder.setRequestPromotedOngoing(true)
                }
            } catch (_: Throwable) {
                // Promotion is best-effort; fall back to a standard ongoing
                // notification on devices without the API.
            }
        }

        val notificationId = if (liveUpdate.isDemo) DEMO_NOTIFICATION_ID else COURSE_NOTIFICATION_ID
        manager.notify(notificationId, builder.build())
    }

    fun cancel(context: Context, liveUpdate: LiveUpdatePackage) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(if (liveUpdate.isDemo) DEMO_NOTIFICATION_ID else COURSE_NOTIFICATION_ID)
    }

    fun cancelKnown(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(COURSE_NOTIFICATION_ID)
        manager.cancel(DEMO_NOTIFICATION_ID)
    }

    fun openChannelSettings(context: Context) {
        ensureChannel(context)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL_ID)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.live_update_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.live_update_channel_description)
        }
        manager.createNotificationChannel(channel)
    }

    private fun contentIntent(context: Context, liveUpdate: LiveUpdatePackage): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_APP
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TARGET_APP_ID, liveUpdate.targetAppId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, 480000 + liveUpdate.keyHash(), intent, flags)
    }

    private fun dismissIntent(context: Context, liveUpdate: LiveUpdatePackage): PendingIntent {
        val intent = Intent(context, LiveUpdateAlarmReceiver::class.java).apply {
            action = LiveUpdateAlarmReceiver.ACTION_DISMISS
            putExtra(LiveUpdateAlarmReceiver.EXTRA_ACCOUNT_KEY, liveUpdate.accountKey)
            putExtra(LiveUpdateAlarmReceiver.EXTRA_IS_DEMO, liveUpdate.isDemo)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, 480001 + liveUpdate.keyHash(), intent, flags)
    }

    private fun LiveUpdatePackage.keyHash(): Int =
        if (isDemo) DEMO_KEY_HASH else accountKey.hashCode()

    private fun emojiTrackerIcon(context: Context, emoji: String): Icon {
        val density = context.resources.displayMetrics.density
        val size = (32 * density).toInt().coerceAtLeast(48)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        bitmap.density = context.resources.displayMetrics.densityDpi
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            textSize = size * 0.78f
        }
        val metrics = paint.fontMetrics
        val baseline = size / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(emoji, size / 2f, baseline, paint)
        return Icon.createWithBitmap(bitmap)
    }

    /** ProgressStyle stores a static integer. Recompute the active value from
     * the persisted East-8 course window whenever a local checkpoint fires. */
    private fun progressAtNow(render: LiveUpdateRender): Int {
        if (render.progressMax <= 0 || render.phase != "active") {
            return render.progress.coerceIn(0, render.progressMax.coerceAtLeast(0))
        }
        val start = render.startAt?.let(::parseLiveUpdateEpochMillis)
        val end = render.endAt?.let(::parseLiveUpdateEpochMillis)
        if (start == null || end == null || end <= start) {
            return render.progress.coerceIn(0, render.progressMax)
        }
        val durationSeconds = ((end - start) / 1000L).toInt().coerceAtLeast(1)
        val elapsedSeconds = ((System.currentTimeMillis() - start) / 1000L)
            .toInt()
            .coerceIn(0, durationSeconds)
        return elapsedSeconds.coerceIn(0, render.progressMax)
    }

    private const val DEMO_KEY_HASH = 198401
}

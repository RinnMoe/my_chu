package moe.rinn.mychu

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import org.json.JSONObject

data class VivoSuperXDemoPayload(
    val operation: Int,
    val title: String,
    val content: String,
    val shortText: String,
    val progressPercent: Int,
    val changedRecord: Int,
    val keepDuration: Int,
) {
    companion object {
        fun fromJson(json: JSONObject): VivoSuperXDemoPayload = VivoSuperXDemoPayload(
            operation = json.optInt("operation", 0),
            title = json.optString("title"),
            content = json.optString("content"),
            shortText = json.optString("shortText"),
            progressPercent = json.optInt("progressPercent", 0),
            changedRecord = json.optInt("changedRecord", 0),
            keepDuration = json.optInt("keepDuration", 0),
        )
    }
}

object VivoSuperXDemoNotifier {
    const val CHANNEL_ID = "mychu_vivo_superx_demo"
    const val NOTIFICATION_ID = 480003
    const val TAG = "VIVO_SUPERX_TAG"
    const val SCENE = "METTING"

    private const val TEMPLATE_PROGRESS = 2
    private const val OPERATION_END = 2
    private const val DEFAULT_END_KEEP_SECONDS = 30

    private const val KEY_OPERATION = "notification.superx.operation"
    private const val KEY_SHOW_NOTIFY = "notification.superx.showNotify"
    private const val KEY_TEMPLATE = "notification.superx.template"
    private const val KEY_SCENE = "notification.superx.scene"
    private const val KEY_CHANGED_RECORD = "notification.superx.changedRecord"
    private const val KEY_KEEP_DURATION = "notification.superx.keepDuration"
    private const val KEY_CLICK_RESP = "notification.superx.clickResp"
    private const val KEY_BASE_INFOS = "notification.superx.baseInfos"
    private const val KEY_INFOS = "notification.superx.infos"
    private const val KEY_SHORT_INFOS = "notification.superx.shortInfos"
    private const val KEY_CAPSULE = "notification.superx.capsule"
    private const val KEY_ISLAND = "notification.superx.island"

    private const val KEY_BASE_ICON = "notification.superx.baseInfos.icon"
    private const val KEY_BASE_TITLE = "notification.superx.baseInfos.title"
    private const val KEY_BASE_CONTENT = "notification.superx.baseInfos.content"

    private const val KEY_INFO_NODE_ICON = "notification.superx.infos.nodeIcon"
    private const val KEY_INFO_INDICATOR_ICON =
        "notification.superx.infos.indicatorIcon"
    private const val KEY_INFO_INDICATOR_LOC = "notification.superx.infos.indicatorLoc"
    private const val KEY_INFO_PROGRESS = "notification.superx.infos.progress"
    private const val KEY_INFO_PROGRESS_COLOR =
        "notification.superx.infos.progressColor"
    private const val KEY_INFO_BG_COLOR = "notification.superx.infos.BgColor"

    private const val KEY_SHORT_ICON = "notification.superx.shortInfos.icon"
    private const val KEY_SHORT_IMAGE = "notification.superx.shortInfos.image"
    private const val KEY_SHORT_IMAGE_CLICK_RESP =
        "notification.superx.shortInfos.imageClickResp"
    private const val KEY_SHORT_ORIGIN_IMAGE =
        "notification.superx.shortInfos.OriginBImage"
    private const val KEY_SHORT_DESCRIBE =
        "notification.superx.shortInfos.describeShort"
    private const val KEY_SHORT_CORE =
        "notification.superx.shortInfos.coreInfoShort"

    private const val KEY_CAPSULE_STATE = "notification.superx.capsule.state"
    private const val KEY_CAPSULE_ICON = "notification.superx.capsule.icon"
    private const val KEY_CAPSULE_CONTENT = "notification.superx.capsule.content"
    private const val KEY_CAPSULE_CONTENT_COLOR =
        "notification.superx.capsule.contentColor"
    private const val KEY_CAPSULE_BG_COLOR =
        "notification.superx.capsule.bgColor"

    private const val KEY_ISLAND_LEFT_TEMPLATE = "island.superx.leftTemplate"
    private const val KEY_ISLAND_LEFT_INFO = "island.superx.leftInfo"
    private const val KEY_ISLAND_RIGHT_TEMPLATE = "island.superx.rightTemplate"
    private const val KEY_ISLAND_RIGHT_INFO = "island.superx.rightInfo"
    private const val KEY_ISLAND_SHOW_TIME = "island.superx.showTime"
    private const val KEY_ISLAND_LEFT_ICON = "island.superx.leftInfo.icon"
    private const val KEY_ISLAND_LEFT_CONTENT = "island.superx.leftInfo.content"
    private const val KEY_ISLAND_RIGHT_ICON = "island.superx.rightInfo.icon"
    private const val KEY_ISLAND_RIGHT_CONTENT = "island.superx.rightInfo.content"
    private const val KEY_ISLAND_RIGHT_BG_COLOR =
        "island.superx.rightInfo.capsuleBgColor"
    private const val KEY_ISLAND_RIGHT_CLICK_RESP =
        "island.superx.rightInfo.clickResp"

    fun post(context: Context, payload: VivoSuperXDemoPayload) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("POST_NOTIFICATIONS permission is not granted")
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
            .setSmallIcon(R.drawable.ic_stat_course)
            .setContentTitle(payload.title)
            .setContentText(payload.content)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(payload.operation != OPERATION_END)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setExtras(bundleFor(context, payload))
            .setContentIntent(contentIntent(context))
        manager.notify(TAG, NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(TAG, NOTIFICATION_ID)
    }

    fun status(context: Context): Map<String, Any?> {
        val manager = context.getSystemService(NotificationManager::class.java)
        return mapOf(
            "supportCustomFun" to reflectSceneBoolean(
                manager,
                "isSupportCustomFun",
                context.packageName,
            ),
            "sceneEnabled" to reflectSceneBoolean(
                manager,
                "getSceneStatus",
                context.packageName,
            ),
        )
    }

    private fun bundleFor(context: Context, payload: VivoSuperXDemoPayload): Bundle {
        val bundle = Bundle().apply {
            putInt(KEY_OPERATION, payload.operation)
            putBoolean(KEY_SHOW_NOTIFY, true)
            putInt(KEY_TEMPLATE, TEMPLATE_PROGRESS)
            putString(KEY_SCENE, SCENE)
            putInt(KEY_CHANGED_RECORD, payload.changedRecord)
            putParcelable(KEY_CLICK_RESP, contentIntent(context))
            if (payload.operation == OPERATION_END) {
                val keepSeconds = if (payload.keepDuration > 0) {
                    payload.keepDuration
                } else {
                    DEFAULT_END_KEEP_SECONDS
                }
                putInt(KEY_KEEP_DURATION, keepSeconds)
            }
        }
        if (payload.operation != OPERATION_END) {
            bundle.putBundle(KEY_BASE_INFOS, baseBundle(context, payload))
            bundle.putBundle(KEY_INFOS, infoBundle(context, payload))
            bundle.putBundle(KEY_SHORT_INFOS, shortInfoBundle(context, payload))
            bundle.putBundle(KEY_CAPSULE, capsuleBundle(context, payload))
            bundle.putBundle(KEY_ISLAND, islandBundle(context, payload))
        }
        return bundle
    }

    private fun baseBundle(context: Context, payload: VivoSuperXDemoPayload): Bundle {
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_course)
        return Bundle().apply {
            putParcelable(KEY_BASE_ICON, icon)
            putCharSequence(KEY_BASE_TITLE, payload.title)
            putCharSequence(KEY_BASE_CONTENT, payload.content)
        }
    }

    private fun infoBundle(context: Context, payload: VivoSuperXDemoPayload): Bundle {
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_course)
        val nodes = ArrayList<android.os.Parcelable>(3)
        repeat(3) { nodes.add(icon) }
        return Bundle().apply {
            putParcelableArrayList(KEY_INFO_NODE_ICON, nodes)
            putParcelable(KEY_INFO_INDICATOR_ICON, icon)
            putInt(KEY_INFO_INDICATOR_LOC, 1)
            putInt(KEY_INFO_PROGRESS, payload.progressPercent.coerceIn(0, 100))
            putInt(KEY_INFO_PROGRESS_COLOR, Color.rgb(79, 146, 199))
            putInt(KEY_INFO_BG_COLOR, Color.argb(26, 0, 0, 0))
        }
    }

    private fun shortInfoBundle(context: Context, payload: VivoSuperXDemoPayload): Bundle {
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_course)
        return Bundle().apply {
            putParcelable(KEY_SHORT_ICON, icon)
            putParcelable(KEY_SHORT_IMAGE, icon)
            putParcelable(KEY_SHORT_IMAGE_CLICK_RESP, contentIntent(context))
            putParcelable(KEY_SHORT_ORIGIN_IMAGE, icon)
            putString(KEY_SHORT_DESCRIBE, payload.content)
            putString(KEY_SHORT_CORE, payload.shortText)
        }
    }

    private fun capsuleBundle(context: Context, payload: VivoSuperXDemoPayload): Bundle {
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_course)
        return Bundle().apply {
            putInt(KEY_CAPSULE_STATE, 1)
            putParcelable(KEY_CAPSULE_ICON, icon)
            putString(KEY_CAPSULE_CONTENT, payload.shortText)
            putInt(KEY_CAPSULE_CONTENT_COLOR, Color.WHITE)
            putInt(KEY_CAPSULE_BG_COLOR, Color.rgb(79, 146, 199))
        }
    }

    private fun islandBundle(context: Context, payload: VivoSuperXDemoPayload): Bundle {
        val icon = Icon.createWithResource(context, R.drawable.ic_stat_course)
        return Bundle().apply {
            putInt(KEY_ISLAND_LEFT_TEMPLATE, 1)
            putInt(KEY_ISLAND_RIGHT_TEMPLATE, 4)
            putInt(KEY_ISLAND_SHOW_TIME, 30)
            putBundle(
                KEY_ISLAND_LEFT_INFO,
                Bundle().apply {
                    putParcelable(KEY_ISLAND_LEFT_ICON, icon)
                    putString(KEY_ISLAND_LEFT_CONTENT, payload.title)
                },
            )
            putBundle(
                KEY_ISLAND_RIGHT_INFO,
                Bundle().apply {
                    putParcelable(KEY_ISLAND_RIGHT_ICON, icon)
                    putString(KEY_ISLAND_RIGHT_CONTENT, payload.shortText)
                    putInt(KEY_ISLAND_RIGHT_BG_COLOR, Color.rgb(79, 146, 199))
                    putParcelable(KEY_ISLAND_RIGHT_CLICK_RESP, contentIntent(context))
                },
            )
        }
    }

    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_APP
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TARGET_APP_ID, "feature.academic.schedule")
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, NOTIFICATION_ID, intent, flags)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.vivo_superx_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.vivo_superx_channel_description)
        }
        manager.createNotificationChannel(channel)
    }

    private fun reflectSceneBoolean(
        manager: NotificationManager,
        methodName: String,
        packageName: String,
    ): Boolean {
        return try {
            val method = NotificationManager::class.java.getDeclaredMethod(
                methodName,
                String::class.java,
                String::class.java,
            )
            method.isAccessible = true
            method.invoke(manager, packageName, SCENE) as? Boolean ?: false
        } catch (_: Throwable) {
            false
        }
    }
}

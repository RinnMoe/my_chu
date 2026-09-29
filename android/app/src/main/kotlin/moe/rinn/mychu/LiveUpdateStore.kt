package moe.rinn.mychu

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.ZoneOffset

data class LiveUpdateRender(
    val title: String,
    val body: String,
    val shortCriticalText: String?,
    val trackerEmoji: String?,
    val countdownAt: Long?,
    val progress: Int,
    val progressMax: Int,
    val requestPromoted: Boolean,
    val ongoing: Boolean,
    val validUntil: Long?,
    val phase: String,
    val startAt: String?,
    val endAt: String?,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("title", title)
        put("body", body)
        if (!shortCriticalText.isNullOrBlank()) put("shortCriticalText", shortCriticalText)
        if (!trackerEmoji.isNullOrBlank()) put("trackerEmoji", trackerEmoji)
        if (countdownAt != null) put("countdownAt", countdownAt)
        put("progress", progress)
        put("progressMax", progressMax)
        put("requestPromoted", requestPromoted)
        put("ongoing", ongoing)
        if (validUntil != null) put("validUntil", validUntil)
        put("phase", phase)
        if (!startAt.isNullOrBlank()) put("startAt", startAt)
        if (!endAt.isNullOrBlank()) put("endAt", endAt)
    }

    companion object {
        fun fromJson(json: JSONObject): LiveUpdateRender = LiveUpdateRender(
            title = json.optString("title"),
            body = json.optString("body"),
            shortCriticalText = json.optString("shortCriticalText").takeIf { it.isNotEmpty() },
            trackerEmoji = json.optString("trackerEmoji").takeIf { it.isNotEmpty() },
            countdownAt = parseLiveUpdateEpochMillis(json.opt("countdownAt")),
            progress = json.optInt("progress"),
            progressMax = json.optInt("progressMax"),
            requestPromoted = json.optBoolean("requestPromoted", false),
            ongoing = json.optBoolean("ongoing", true),
            validUntil = parseLiveUpdateEpochMillis(json.opt("validUntil")),
            phase = json.optString("phase", "active"),
            startAt = json.optString("startAt").takeIf { it.isNotEmpty() },
            endAt = json.optString("endAt").takeIf { it.isNotEmpty() },
        )

    }
}

/** Parses Dart ISO strings, including the East-8 wall-clock form used by the
 * shared live-update contract, without relying on the device timezone. */
fun parseLiveUpdateEpochMillis(value: Any?): Long? = when (value) {
    is Number -> value.toLong().takeIf { it >= 0 }
    is String -> value.toLongOrNull()?.takeIf { it >= 0 }
        ?: runCatching { java.time.Instant.parse(value).toEpochMilli() }.getOrNull()
        ?: runCatching {
            LocalDateTime.parse(value).toInstant(ZoneOffset.ofHours(8)).toEpochMilli()
        }.getOrNull()
    else -> null
}

data class LiveUpdateBoundary(
    val at: Long,
    val render: LiveUpdateRender,
    val cancel: Boolean,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("at", at)
        put("render", render.toJson())
        put("cancel", cancel)
    }

    companion object {
        fun fromJson(json: JSONObject): LiveUpdateBoundary = LiveUpdateBoundary(
            at = parseLiveUpdateEpochMillis(json.opt("at")) ?: 0L,
            render = LiveUpdateRender.fromJson(json.optJSONObject("render") ?: JSONObject()),
            cancel = json.optBoolean("cancel", false),
        )
    }
}

data class LiveUpdatePackage(
    val accountKey: String,
    val definitionId: String,
    val targetAppId: String,
    val render: LiveUpdateRender,
    val boundaries: List<LiveUpdateBoundary>,
    val isDemo: Boolean,
    val postImmediately: Boolean,
    val cancelExisting: Boolean,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("accountKey", accountKey)
        put("definitionId", definitionId)
        put("targetAppId", targetAppId)
        put("render", render.toJson())
        put(
            "boundaries",
            org.json.JSONArray(boundaries.map { it.toJson() }),
        )
        put("isDemo", isDemo)
        put("postImmediately", postImmediately)
        put("cancelExisting", cancelExisting)
    }

    companion object {
        fun fromJson(json: JSONObject): LiveUpdatePackage {
            val rawBoundaries = json.optJSONArray("boundaries") ?: org.json.JSONArray()
            val boundaries = buildList {
                for (index in 0 until rawBoundaries.length()) {
                    rawBoundaries.optJSONObject(index)?.let { add(LiveUpdateBoundary.fromJson(it)) }
                }
            }
            return LiveUpdatePackage(
                accountKey = json.optString("accountKey"),
                definitionId = json.optString("definitionId"),
                targetAppId = json.optString("targetAppId"),
                render = LiveUpdateRender.fromJson(json.optJSONObject("render") ?: JSONObject()),
                boundaries = boundaries,
                isDemo = json.optBoolean("isDemo", false),
                postImmediately = json.optBoolean("postImmediately", true),
                cancelExisting = json.optBoolean("cancelExisting", false),
            )
        }
    }
}

/** Small, bounded local store for Android Live Update packages. */
object LiveUpdateStore {
    const val DEMO_KEY = "demo"

    private const val PREFS_NAME = "mychu_live_updates"
    private const val ACCOUNT_PREFIX = "account."
    private const val DISMISSED_PREFIX = "dismissed."

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun keyForAccount(accountKey: String): String = "$ACCOUNT_PREFIX$accountKey"

    fun save(context: Context, key: String, liveUpdate: LiveUpdatePackage) {
        prefs(context).edit().putString(key, liveUpdate.toJson().toString()).apply()
    }

    fun read(context: Context, key: String): LiveUpdatePackage? {
        val raw = prefs(context).getString(key, null) ?: return null
        return try {
            LiveUpdatePackage.fromJson(JSONObject(raw))
        } catch (_: Throwable) {
            null
        }
    }

    fun delete(context: Context, key: String) {
        prefs(context).edit().remove(key).apply()
    }

    fun isDismissed(context: Context, liveUpdate: LiveUpdatePackage): Boolean {
        if (liveUpdate.isDemo) return false
        val raw = prefs(context).getString(dismissedKey(liveUpdate.accountKey), null)
            ?: return false
        return try {
            val record = JSONObject(raw)
            val eventKey = eventKey(liveUpdate)
            val until = record.optLong("until", 0L)
            if (until <= System.currentTimeMillis()) {
                prefs(context).edit().remove(dismissedKey(liveUpdate.accountKey)).apply()
                false
            } else record.optString("eventKey") == eventKey
        } catch (_: Throwable) {
            false
        }
    }

    fun markDismissed(context: Context, liveUpdate: LiveUpdatePackage) {
        if (liveUpdate.isDemo) return
        val until = liveUpdate.render.endAt?.let { raw ->
            parseLiveUpdateEpochMillis(raw)
                ?: (System.currentTimeMillis() + 24 * 60 * 60 * 1000L)
        } ?: (System.currentTimeMillis() + 24 * 60 * 60 * 1000L)
        prefs(context).edit().putString(
            dismissedKey(liveUpdate.accountKey),
            JSONObject().apply {
                put("eventKey", eventKey(liveUpdate))
                put("until", until)
            }.toString(),
        ).apply()
    }

    fun readAllFormal(context: Context): List<LiveUpdatePackage> =
        prefs(context).all.entries
            .filter { it.key.startsWith(ACCOUNT_PREFIX) }
            .mapNotNull { (_, value) ->
                val raw = value as? String ?: return@mapNotNull null
                try {
                    LiveUpdatePackage.fromJson(JSONObject(raw))
                } catch (_: Throwable) {
                    null
                }
            }

    fun clearAll(context: Context) {
        val editor = prefs(context).edit()
        prefs(context).all.keys
            .filter { it.startsWith(ACCOUNT_PREFIX) || it == DEMO_KEY }
            .forEach(editor::remove)
        prefs(context).all.keys
            .filter { it.startsWith(DISMISSED_PREFIX) }
            .forEach(editor::remove)
        editor.apply()
    }

    private fun dismissedKey(accountKey: String): String = "$DISMISSED_PREFIX$accountKey"

    private fun eventKey(liveUpdate: LiveUpdatePackage): String =
        "${liveUpdate.definitionId}|${liveUpdate.render.startAt}|${liveUpdate.render.endAt}"
}

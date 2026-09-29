package moe.rinn.mychu

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class ScheduledAlert(
    val accountKey: String,
    val providerId: String,
    val eventId: String,
    val triggerAt: Long,
    val title: String,
    val body: String?,
    val targetAppId: String?,
    val validUntil: Long,
) {
    val key: String get() = "$providerId|$eventId|$triggerAt"

    fun toJson(): JSONObject = JSONObject().apply {
        put("accountKey", accountKey)
        put("providerId", providerId)
        put("eventId", eventId)
        put("triggerAt", triggerAt)
        put("title", title)
        if (!body.isNullOrBlank()) put("body", body)
        if (!targetAppId.isNullOrBlank()) put("targetAppId", targetAppId)
        put("validUntil", validUntil)
    }

    companion object {
        fun fromJson(json: JSONObject): ScheduledAlert? {
            val accountKey = json.optString("accountKey")
            val providerId = json.optString("providerId")
            val eventId = json.optString("eventId")
            val triggerAt = json.optLong("triggerAt", -1)
            val title = json.optString("title")
            val validUntil = json.optLong("validUntil", triggerAt + 24 * 60 * 60 * 1000)
            if (accountKey.isBlank() || providerId.isBlank() || eventId.isBlank() ||
                triggerAt <= 0 || title.isBlank()
            ) return null
            return ScheduledAlert(
                accountKey = accountKey,
                providerId = providerId,
                eventId = eventId,
                triggerAt = triggerAt,
                title = title.take(80),
                body = json.optString("body").takeIf { it.isNotBlank() }?.take(160),
                targetAppId = json.optString("targetAppId").takeIf { it.isNotBlank() },
                validUntil = validUntil.coerceAtLeast(triggerAt),
            )
        }
    }
}

object ScheduledAlertStore {
    private const val PREFS_NAME = "mychu_scheduled_alerts"
    private const val SCHEDULE_PREFIX = "schedule."
    private const val RECEIPTS_KEY = "receipts"
    private const val EXACT_REQUESTED_KEY = "exact_requested"
    private const val MAX_RECEIPTS = 64
    const val MAX_SCHEDULED_ALERTS = 64

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun scheduleKey(accountKey: String, providerId: String) =
        "$SCHEDULE_PREFIX$accountKey.$providerId"

    fun exactRequested(context: Context): Boolean =
        prefs(context).getBoolean(EXACT_REQUESTED_KEY, false)

    fun setExactRequested(context: Context, requested: Boolean) {
        prefs(context).edit().putBoolean(EXACT_REQUESTED_KEY, requested).apply()
    }

    fun replace(
        context: Context,
        accountKey: String,
        providerId: String,
        alerts: List<ScheduledAlert>,
    ) {
        val array = JSONArray(alerts.map { it.toJson() })
        prefs(context).edit()
            .putString(scheduleKey(accountKey, providerId), array.toString())
            .apply()
    }

    fun replaceAll(context: Context, alerts: List<ScheduledAlert>) {
        val preferences = prefs(context)
        val editor = preferences.edit()
        preferences.all.keys
            .filter { it.startsWith(SCHEDULE_PREFIX) }
            .forEach(editor::remove)
        alerts.groupBy { it.accountKey to it.providerId }.forEach { (owner, values) ->
            val array = JSONArray(values.map { it.toJson() })
            editor.putString(scheduleKey(owner.first, owner.second), array.toString())
        }
        editor.apply()
    }

    fun readProvider(context: Context, accountKey: String, providerId: String): List<ScheduledAlert> =
        parse(prefs(context).getString(scheduleKey(accountKey, providerId), null))

    fun readAll(context: Context): List<ScheduledAlert> =
        prefs(context).all.entries
            .filter { it.key.startsWith(SCHEDULE_PREFIX) }
            .flatMap { parse(it.value as? String) }

    fun remove(context: Context, alert: ScheduledAlert) {
        val remaining = readProvider(context, alert.accountKey, alert.providerId)
            .filterNot { it.key == alert.key }
        replace(context, alert.accountKey, alert.providerId, remaining)
    }

    fun clearProvider(context: Context, accountKey: String, providerId: String) {
        prefs(context).edit().remove(scheduleKey(accountKey, providerId)).apply()
    }

    fun clearAll(context: Context) {
        val editor = prefs(context).edit()
        prefs(context).all.keys.filter { it.startsWith(SCHEDULE_PREFIX) }.forEach(editor::remove)
        editor.remove(RECEIPTS_KEY).apply()
    }

    fun addReceipt(context: Context, alert: ScheduledAlert) {
        val current = parseReceipts(prefs(context).getString(RECEIPTS_KEY, null)).toMutableList()
        current.removeAll { it.optString("key") == alert.key }
        current.add(JSONObject().apply {
            put("key", alert.key)
            put("accountKey", alert.accountKey)
            put("providerId", alert.providerId)
            put("eventId", alert.eventId)
            put("title", alert.title)
            if (!alert.body.isNullOrBlank()) put("body", alert.body)
            if (!alert.targetAppId.isNullOrBlank()) put("targetAppId", alert.targetAppId)
            put("validUntil", alert.validUntil)
            put("deliveredAt", System.currentTimeMillis())
        })
        val bounded = current.takeLast(MAX_RECEIPTS)
        prefs(context).edit().putString(RECEIPTS_KEY, JSONArray(bounded).toString()).apply()
    }

    fun consumeReceipts(context: Context): List<Map<String, Any?>> {
        val values = parseReceipts(prefs(context).getString(RECEIPTS_KEY, null))
        prefs(context).edit().remove(RECEIPTS_KEY).apply()
        return values.map { json ->
            buildMap {
                for (key in listOf("key", "accountKey", "providerId", "eventId", "title", "body", "targetAppId", "validUntil", "deliveredAt")) {
                    if (json.has(key)) put(key, json.opt(key))
                }
            }
        }
    }

    private fun parse(raw: String?): List<ScheduledAlert> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    array.optJSONObject(index)?.let(ScheduledAlert::fromJson)?.let(::add)
                }
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun parseReceipts(raw: String?): List<JSONObject> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) array.optJSONObject(index)?.let(::add)
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }
}
